import XCTest
import XCTVapor
@testable import MixpanelVapor
import Fakery

final class MixpanelVaporTests: XCTestCase {
    
    var app: Application!
    static let testUserId = UUID().uuidString
    static let faker = Faker()
    
    override func setUp() async throws {
        app = Application(.testing)
        // Please don't do any funny business with this token, it's a dommy project to run unit tests against.
        let configuration = MixpanelConfiguration(token: "b939a52a74c47df96d3ffc66c5c3dcfd")
        app.mixpanel.configuration = configuration
    }
    
    func testTrackAnonymousEvent() async {
        await app.mixpanel.track(distinctId: nil, name: "test_event_empty_distinct_id")
    }
    
    func testTrackEvent() async {
        await app.mixpanel.track(distinctId: Self.testUserId, name: "test_event")
    }
    
    func testTrackEventWithRequestData() async throws {
        
        app.get("trackEvent") { req async throws in
            
            await req.mixpanel.track(distinctId: Self.testUserId, name: "test_event_with_request_metadata", request: req)
            
            return "ok"
        }
        
        try await app.test(.GET, "trackEvent")
    }
    
    func testIdentifyUser() async throws {
        
        await app.mixpanel.peopleSet(distinctId: Self.testUserId, setParams: ["hello": "there", "$email": Self.faker.name.firstName().lowercased() + "@example.com", "$name": Self.faker.name.name(), "$user_id": Self.testUserId])
    }
    
    func testDeleteUser() async throws {
        await app.mixpanel.peopleDelete(distinctId: Self.testUserId)
    }
}
