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

        try? await Task.sleep(for: .milliseconds(5))
        XCTAssertEqual(service.statusMessage, "First")

        try? await Task.sleep(for: .milliseconds(55))
        XCTAssertEqual(service.statusMessage, "Second")

        try? await Task.sleep(for: .milliseconds(55))
        XCTAssertEqual(service.statusMessage, "Ready")
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
}
