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
}
