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
await application.mixpanel.track(distinctId: "<user id>", name: "my_event", params: ["$user_id": profile.id, "a": 123])
await request.mixpanel.track(distinctId: "<user id>", name: "my_event", params: ["$user_id": profile.id, "a": 123])

// enhances the metadata (user agent, country, ...) by parsing the headers and ip from the request
await request.mixpanel.track(distinctId: "<user id>", name: "my_event", request: request, params: ["$user_id": profile.id, "a": 123])
```

### Identify a user
```swift
await application.mixpanel.peopleSet(distinctId: "<user id>", request: request, setParams: ["$email": "john@example.com", "num_cats": 5])
```

### Delete a user
```swift
await application.mixpanel.peopleDelete(distinctId: "<user id>")
```

A list of mixpanel properties to assign a name, email, and other properties to a mixpanel identity can be found [here](https://docs.mixpanel.com/docs/data-structure/user-profiles#reserved-user-properties).

I've only implemented very basic feature set that fits my needs at this point. Will extend this package as I have the need for it, but contributions are very welcome.
