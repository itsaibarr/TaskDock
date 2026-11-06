import XCTest
@testable import TaskDock

/// Touches the real Dock (about 15 s). Run only on purpose: TASKDOCK_LIVE_DOCK=1 ./scripts/test.sh
final class LiveDockTests: XCTestCase {
    /// The hard case: finishing right after starting, while the restarted Dock is still settling.
    func testRestoreRightAfterApplyGivesBackTheSameDock() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TASKDOCK_LIVE_DOCK"] == "1")
        let before = try XCTUnwrap(Dock.snapshot())
        let backup = FileManager.default.temporaryDirectory.appendingPathComponent("taskdock-live-test.plist")

        Dock.apply([AppRef(bundleID: "net.imput.helium", name: "Helium", path: "/Applications/Helium.app")], over: before, backup: backup)
        XCTAssertEqual(Dock.appIDs(Dock.snapshot()), ["net.imput.helium"])

        Dock.restore(before)
        XCTAssertEqual(Dock.appIDs(Dock.snapshot()), Dock.appIDs(before))
        Thread.sleep(forTimeInterval: 8) // the restarted Dock must not overwrite us later
        XCTAssertEqual(Dock.appIDs(Dock.snapshot()), Dock.appIDs(before))
    }
}
