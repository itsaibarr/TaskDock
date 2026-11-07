import Foundation
import Network

/// Local WebSocket server the browser extension connects to (127.0.0.1 only, extension origins only).
/// Simpler than native messaging: no per-browser host manifest, works in Helium and Brave alike.
@MainActor
final class Bridge {
    static let port: NWEndpoint.Port = {
        #if DEBUG // the end-to-end test runs beside the installed app, on its own port
        if let p = ProcessInfo.processInfo.environment["TASKDOCK_PORT"].flatMap(UInt16.init).flatMap(NWEndpoint.Port.init(rawValue:)) { return p }
        #endif
        return 47123
    }()

    var stateMessage: () -> [String: Any] = { [:] }
    /// Connected browsers, and whether any still runs older extension code (v1, can't save tabs until reloaded).
    var onBrowsersChanged: (_ count: Int, _ outdated: Bool) -> Void = { _, _ in }
    /// The current task window's tabs, by session.
    var onTabs: (UUID, [String]) -> Void = { _, _ in }

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var outdated = Set<ObjectIdentifier>()

    func start() {
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        ws.maximumMessageSize = 64 * 1024 // the extension only sends tiny JSON messages
        ws.setClientRequestHandler(.main) { _, headers in
            let origin = headers.first { $0.name.lowercased() == "origin" }?.value ?? ""
            let ok = origin.hasPrefix("chrome-extension://")
            return NWProtocolWebSocket.Response(status: ok ? .accept : .reject, subprotocol: nil, additionalHeaders: nil)
        }
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        do {
            let l = try NWListener(using: params, on: Self.port)
            l.newConnectionHandler = { [weak self] c in
                MainActor.assumeIsolated { self?.accept(c) }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            NSLog("TaskDock: bridge failed to start: \(error)")
        }
    }

    private func accept(_ c: NWConnection) {
        let key = ObjectIdentifier(c)
        connections[key] = c
        c.stateUpdateHandler = { [weak self] st in
            MainActor.assumeIsolated {
                switch st {
                case .failed, .cancelled:
                    self?.connections[key] = nil
                    self?.outdated.remove(key)
                    self?.changed()
                default: break
                }
            }
        }
        c.start(queue: .main)
        receive(c)
        changed()
    }

    private func changed() { onBrowsersChanged(connections.count, !outdated.isEmpty) }

    private func receive(_ c: NWConnection) {
        c.receiveMessage { [weak self] data, ctx, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                let meta = ctx?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
                if error != nil || meta?.opcode == .close || (data == nil && isComplete && meta == nil) {
                    c.cancel()
                    return
                }
                if let data, let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self.handle(msg, from: c)
                }
                self.receive(c)
            }
        }
    }

    private func handle(_ msg: [String: Any], from c: NWConnection) {
        switch msg["type"] as? String {
        case "hello":
            // v2 reports tabs while a task runs.
            if (msg["v"] as? Int ?? 1) < 2 { outdated.insert(ObjectIdentifier(c)) } else { outdated.remove(ObjectIdentifier(c)) }
            changed()
            send(stateMessage(), to: c)
        case "tabs":
            guard let id = (msg["session"] as? String).flatMap(UUID.init), let urls = msg["urls"] as? [String] else { return }
            // Only web pages, so a saved tab can't become anything else when it's reopened.
            onTabs(id, Array(urls.filter { $0.hasPrefix("https://") || $0.hasPrefix("http://") }.prefix(50)))
        default: break // "ping" keeps the extension's service worker alive
        }
    }

    func broadcast(_ msg: [String: Any]) {
        for c in connections.values { send(msg, to: c) }
    }

    private func send(_ msg: [String: Any], to c: NWConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: msg) else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let ctx = NWConnection.ContentContext(identifier: "msg", metadata: [meta])
        c.send(content: data, contentContext: ctx, isComplete: true, completion: .contentProcessed { _ in })
    }
}
