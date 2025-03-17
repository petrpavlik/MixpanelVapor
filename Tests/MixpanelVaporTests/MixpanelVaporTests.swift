@preconcurrency import Fakery
import XCTVapor
import XCTest

@testable import MixpanelVapor

final class MixpanelVaporTests: XCTestCase {

    var app: Application!
    var mixpanelClient: Mixpanel!
    static let testUserId = UUID().uuidString
    static let faker = Faker()

    override func setUp() async throws {
        app = try await Application.make(.testing)
        // Please don't do any funny business with this token, it's a dummy project to run unit tests against.
        let configuration = MixpanelConfiguration(token: "b939a52a74c47df96d3ffc66c5c3dcfd")
        app.mixpanel.configuration = configuration
        try await app.asyncBoot()
        mixpanelClient = app.mixpanel.client!
    }

    override func tearDown() async throws {
        await app.mixpanel.shutdown()
        let pendingEvents = await mixpanelClient.pendingEvents
        XCTAssertEqual(pendingEvents.count, 0)
        try await app.asyncShutdown()
    }

    func testTrackAnonymousEvent() async {
        app.mixpanel.track(distinctId: nil, name: "test_event_empty_distinct_id")
        await Task.yield()
        let pendingEvents = await mixpanelClient.pendingEvents
        XCTAssertEqual(pendingEvents.count, 1)
    }

    func testTrackEvent() async {
        app.mixpanel.track(distinctId: Self.testUserId, name: "test_event")
        await Task.yield()
        let pendingEvents = await mixpanelClient.pendingEvents
        XCTAssertEqual(pendingEvents.count, 1)
    }

    func testTrackEventWithRequestData() async throws {

        app.get("trackEvent") { req async throws in

            req.mixpanel.track(
                distinctId: Self.testUserId, name: "test_event_with_request_metadata", request: req)

            return "ok"
        }

        try await app.test(.GET, "trackEvent")
        let pendingEvents = await mixpanelClient.pendingEvents
        XCTAssertEqual(pendingEvents.count, 1)
    }

    func testTrackAndManuallyUploadEvent() async {
        app.mixpanel.track(distinctId: nil, name: "test_event_manual_upload")
        await app.mixpanel.flush()
        await Task.yield()  // FIXME: is this going to prevent the CI on GH from failing?
        let pendingEvents = await mixpanelClient.pendingEvents
        XCTAssertEqual(pendingEvents.count, 0)
    }

    func testTrackAndAutomaticallyUploadEvent() async throws {
        app.mixpanel.track(distinctId: nil, name: "test_event_scheduled_upload")
        await Task.yield()
        var pendingEvents = await mixpanelClient.pendingEvents
        XCTAssertEqual(pendingEvents.count, 1)
        try await Task.sleep(for: .milliseconds(500))
        pendingEvents = await mixpanelClient.pendingEvents
        XCTAssertEqual(pendingEvents.count, 1)
        try await Task.sleep(for: .milliseconds(500))  // event triggered
        try await Task.sleep(for: .milliseconds(100))  // uplod time
        pendingEvents = await mixpanelClient.pendingEvents
        XCTAssertEqual(pendingEvents.count, 0)
    }

    func testIdentifyUser() async throws {

        await app.mixpanel.peopleSet(
            distinctId: Self.testUserId,
            setParams: [
                "hello": "there",
                "$email": .string(Self.faker.name.firstName().lowercased() + "@example.com"),
                "$name": .string(Self.faker.name.name()), "$user_id": .string(Self.testUserId),
            ])
    }

    func testDeleteUser() async throws {
        await app.mixpanel.peopleDelete(distinctId: Self.testUserId)
    }

    func testMixpanelProperty() {
        var props = [String: MixpanelProperty]()
        let str = "hello"
        props["hello"] = "\(str)"
        props["string"] = "hello"
        props["number"] = 1
        props["bool"] = true
        props["date"] = .date(.now)

    }
}
