import Testing
import Foundation
@testable import MacSift

@Suite("TimeMachineService")
struct TimeMachineServiceTests {
    @Test func parsesSnapshotOutput() {
        let output = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-04-01-120000.local
        com.apple.TimeMachine.2026-04-10-080000.local
        """

        let snapshots = TimeMachineService.parseSnapshots(from: output)

        #expect(snapshots.count == 2)
        #expect(snapshots[0].identifier == "com.apple.TimeMachine.2026-04-01-120000.local")
        #expect(snapshots[0].dateString == "2026-04-01-120000")
        #expect(snapshots[1].identifier == "com.apple.TimeMachine.2026-04-10-080000.local")
    }

    @Test func parsesEmptyOutput() {
        let output = "Snapshots for disk /:\n"
        let snapshots = TimeMachineService.parseSnapshots(from: output)
        #expect(snapshots.isEmpty)
    }

    @Test func handlesNoSnapshotsMessage() {
        let output = ""
        let snapshots = TimeMachineService.parseSnapshots(from: output)
        #expect(snapshots.isEmpty)
    }
}
