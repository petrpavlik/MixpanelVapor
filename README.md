# MixpanelVapor

MixpanelVapor is a library for tracking events to Mixpanel from your [Vapor](https://vapor.codes) server-side Swift applications.

## Initialization

Provide your mixpanel token (the same one you'd use for client-side mixpanel tracking)

```swift
import MixpanelVapor

public func configure(_ app: Application) throws {
    //...
                                           
    app.mixpanel.configuration = .init(token: "YOUR_MIXPANEL_TOKEN")
    
    // ...
}
```

## Usage

### Log an event
```swift
application.mixpanel.track(distinctId: "<user id>", name: "my_event", params: ["$user_id": .string(profile.id), "a": 123])
request.mixpanel.track(distinctId: "<user id>", name: "my_event", params: ["$user_id": .string(profile.id), "a": 123])

// enhances the metadata (user agent, country, ...) by parsing the headers and ip from the request
request.mixpanel.track(distinctId: "<user id>", name: "my_event", request: request, params: ["$user_id": .string(profile.id), "a": 123])
```

### New in 2.0
- The track method is not `async` anymore and events are periodically uploaded in batches.
- You can call `await mixpanel.flush()` to trigger an immediate upload.
- All pending events will be automatically uploaded as a part of the shut down flow.


### Identify a user
```swift
await application.mixpanel.peopleSet(distinctId: "<user id>", request: request, setParams: ["$email": .string("john@example.com"), "num_cats": .int(5)])
```

### Delete a user
```swift
await application.mixpanel.peopleDelete(distinctId: "<user id>")
```

A list of mixpanel properties to assign a name, email, and other properties to a mixpanel identity can be found [here](https://docs.mixpanel.com/docs/data-structure/user-profiles#reserved-user-properties).

I've only implemented very basic feature set that fits my needs at this point. Will extend this package as I have the need for it, but contributions are very welcome.

## Plans for V3
- Implement [Async Service Lifecycle](https://github.com/swift-server/swift-service-lifecycle) and deprecate `shutdown()` method
- Swift 6 (possibly 6.1 or even 6.2) only
- Requires Vapor 5
- Move from XCTest to Swift testing
- Drop dependency on Swift Atomics package
