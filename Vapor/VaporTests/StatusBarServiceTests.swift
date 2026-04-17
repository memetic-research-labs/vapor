import XCTest
@testable import Vapor

@MainActor
final class StatusBarServiceTests: XCTestCase {

    func testRecordsEventsWithMetadata() {
        let service = StatusBarService(minimumDisplayDuration: .milliseconds(10), maximumRetainedEvents: 10)

        service.log(
            "Stored vector",
            domain: .vectorization,
            level: .success,
            metadata: ["embeddingID": "abc123"]
        )

        XCTAssertEqual(service.events.count, 1)
        XCTAssertEqual(service.events.first?.domain, .vectorization)
        XCTAssertEqual(service.events.first?.level, .success)
        XCTAssertEqual(service.events.first?.metadata["embeddingID"], "abc123")
    }

    func testQueuedFooterMessagesDisplayInOrder() async {
        let service = StatusBarService(minimumDisplayDuration: .milliseconds(40), maximumRetainedEvents: 10)

        service.setTransient("First")
        service.setTransient("Second")

        XCTAssertEqual(service.statusMessage, "Ready")

        await waitForStatus("First", in: service)
        await waitForStatus("Second", in: service)
        await waitForStatus("Ready", in: service)
    }

    func testRetainsOnlyMaximumNumberOfEvents() {
        let service = StatusBarService(minimumDisplayDuration: .milliseconds(10), maximumRetainedEvents: 2)

        service.log("One", domain: .system)
        service.log("Two", domain: .system)
        service.log("Three", domain: .system)

        XCTAssertEqual(service.events.count, 2)
        XCTAssertEqual(service.events.first?.message, "Two")
        XCTAssertEqual(service.events.last?.message, "Three")
    }

    private func waitForStatus(
        _ expected: String,
        in service: StatusBarService,
        timeout: Duration = .seconds(1)
    ) async {
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            if service.statusMessage == expected {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for status '\(expected)'. Last value: '\(service.statusMessage)'")
    }
}
