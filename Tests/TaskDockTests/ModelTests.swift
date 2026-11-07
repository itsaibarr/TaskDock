import XCTest
@testable import TaskDock

final class ModelTests: XCTestCase {
    func testBrowsersAreDetected() {
        XCTAssertTrue(AppRef(bundleID: "com.apple.Safari", name: "Safari", path: "/Applications/Safari.app").isBrowser)
        XCTAssertFalse(AppRef(bundleID: "com.apple.Notes", name: "Notes", path: "/System/Applications/Notes.app").isBrowser)
    }

    func testElapsed() {
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(elapsedText(since: start, now: start.addingTimeInterval(59)), "0m")
        XCTAssertEqual(elapsedText(since: start, now: start.addingTimeInterval(25 * 60)), "25m")
        XCTAssertEqual(elapsedText(since: start, now: start.addingTimeInterval(65 * 60)), "1h 05m")
    }

    func testDockTileMatchesDockFormat() throws {
        let tile = Dock.tile(AppRef(bundleID: "net.imput.helium", name: "Helium", path: "/Applications/Helium.app"))
        XCTAssertEqual(tile["tile-type"] as? String, "file-tile")
        let data = try XCTUnwrap(tile["tile-data"] as? [String: Any])
        XCTAssertEqual(data["bundle-identifier"] as? String, "net.imput.helium")
        let file = try XCTUnwrap(data["file-data"] as? [String: Any])
        XCTAssertEqual(file["_CFURLString"] as? String, "file:///Applications/Helium.app/")
        XCTAssertNoThrow(try PropertyListSerialization.data(fromPropertyList: [tile], format: .binary, options: 0))
    }

    func testSessionRoundTrips() throws {
        let s = Session(template: Template(name: "Writing"), goal: "Draft intro", visibleApps: ["a"], dock: Data([1, 2]))
        let back = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.goal, "Draft intro")
        XCTAssertEqual(back.dock, Data([1, 2]))
    }

    func testOldTemplatesWithoutResumeStillLoad() throws {
        let json = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Math","emoji":"🧠","apps":[],"startShortcut":"","endShortcut":"","lastStopNote":""}]"#
        let t = try JSONDecoder().decode([Template].self, from: Data(json.utf8))
        XCTAssertNil(t[0].resume)
    }

    func testObsidianActiveNote() {
        let ws = #"{"main":{"children":[{"children":[{"id":"a","type":"leaf","state":{"type":"markdown","state":{"file":"Old.md"}}},{"id":"b","type":"leaf","state":{"type":"markdown","state":{"file":"Math/Week 3.md"}}}]}]},"left":{"children":[{"id":"x","type":"leaf","state":{"type":"file-explorer","state":{}}}]},"active":"b","lastOpenFiles":["Recent.md"]}"#
        XCTAssertEqual(Snapshot.activeFile(Data(ws.utf8)), "Math/Week 3.md")
        // Sidebar focused: fall back to the most recently opened file.
        XCTAssertEqual(Snapshot.activeFile(Data(ws.replacingOccurrences(of: #""active":"b""#, with: #""active":"x""#).utf8)), "Recent.md")
    }

    func testResumeItemTitles() {
        XCTAssertEqual(Resume.Item(app: "com.apple.Preview", url: URL(fileURLWithPath: "/Books/Calculus.pdf")).title, "Calculus")
        XCTAssertEqual(Resume.Item(app: "md.obsidian", url: Snapshot.obsidianLink("/Vault/Math/Week 3.md")).title, "Week 3")
    }

    func testAeroSpaceWindowList() {
        let w = AeroSpace.parse("95536|md.obsidian|2\n95537|com.apple.Preview|3\n1|x|\n")
        XCTAssertEqual(w, [.init(id: "95536", app: "md.obsidian", workspace: "2"), .init(id: "95537", app: "com.apple.Preview", workspace: "3")])
    }

    func testPhiSpaceMatchesTemplateNameUnlessChosen() {
        let spaces = [Phi.Space(id: "a", title: "Default"), Phi.Space(id: "b", title: "further math")]
        var t = Template(name: "Further Math")
        XCTAssertEqual(Phi.space(for: t, in: spaces)?.id, "b")
        t.phiSpace = "Default"
        XCTAssertEqual(Phi.space(for: t, in: spaces)?.id, "a")
    }

    func testPhiNewSpaceMenuItem() {
        XCTAssertTrue(Phi.isNewSpace("New Space"))
        XCTAssertTrue(Phi.isNewSpace("Create a New Space…"))
        XCTAssertFalse(Phi.isNewSpace("New Incognito Space"))
        XCTAssertFalse(Phi.isNewSpace("New Tab"))
    }
}
