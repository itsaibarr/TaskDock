import AppKit
import EventKit

/// A calendar event happening now (or soon), offered at the top of the picker.
struct CalendarSuggestion: Equatable {
    let title: String
    let start: Date
    let end: Date
    let calendar: String
    /// Template whose name appears in the event title, if any.
    let template: Template?

    var time: String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return "\(f.string(from: start))–\(f.string(from: end))"
    }
}

/// Reads the calendars macOS knows about: iCloud, Google (via System Settings › Internet Accounts), Exchange…
@MainActor
final class CalendarFeed: ObservableObject {
    static let shared = CalendarFeed()
    private let store = EKEventStore()
    @Published private(set) var status = EKEventStore.authorizationStatus(for: .event)

    var connected: Bool { status == .fullAccess }

    /// Asks once; after a refusal only System Settings can turn it back on.
    func connect() {
        if status == .notDetermined {
            Task {
                _ = try? await store.requestFullAccessToEvents()
                status = EKEventStore.authorizationStatus(for: .event)
            }
        } else if !connected,
                  let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The event in progress (or starting within 15 minutes) that best fits a task. All-day events are skipped.
    func suggestion(for templates: [Template]) -> CalendarSuggestion? {
        #if DEBUG
        if Debug.enabled {
            return CalendarSuggestion(title: "Writing — chapter 3", start: Date().addingTimeInterval(-600),
                                      end: Date().addingTimeInterval(3000), calendar: "Work",
                                      template: match("Writing — chapter 3", templates))
        }
        #endif
        status = EKEventStore.authorizationStatus(for: .event)
        guard connected else { return nil }
        let now = Date()
        let events = store.events(matching: store.predicateForEvents(withStart: now.addingTimeInterval(-12 * 3600),
                                                                     end: now.addingTimeInterval(15 * 60), calendars: nil))
            .filter { !$0.isAllDay && $0.endDate > now && $0.status != .canceled && !($0.title ?? "").isEmpty }
        // Prefer what's on right now, the one that started most recently; otherwise the next to start.
        let event = events.filter { $0.startDate <= now }.max { $0.startDate < $1.startDate }
            ?? events.min { $0.startDate < $1.startDate }
        guard let e = event, let title = e.title else { return nil }
        return CalendarSuggestion(title: title, start: e.startDate, end: e.endDate,
                                  calendar: e.calendar?.title ?? "", template: match(title, templates))
    }

    /// Longest template name contained in the event title ("Deep work — Writing" → "Writing").
    private func match(_ title: String, _ templates: [Template]) -> Template? {
        templates.filter { $0.name.count >= 3 && title.localizedCaseInsensitiveContains($0.name) }
            .max { $0.name.count < $1.name.count }
    }
}
