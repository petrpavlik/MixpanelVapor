# MixpanelVapor

MixpanelVapor is a library for tracking events to Mixpanel from your Vapor server-side Swift applications.

## Initialization

Mixpanel recommends using a service account and their `/import` endpoint for server-side apps so that's what this package uses.
It allows to add things like batch import of events at a large scale in the future.

```swift
import MixpanelVapor

public func configure(_ app: Application) throws {
    //...
    
    let mixpanelServiceAccount = BasicAuth(username: "aaaaa.bbbbb.mp-service-account",
                                           password: "aaabbb111222"))
                                           
    app.mixpanel.configuration = .init(projectId: "1234567",
                                       authorization: mixpanelServiceAccount)
    
    // ...
}
```

## Usage
```swift
await application.mixpanel.track(name: "my_event", params: ["a": 123])
await request.mixpanel.track(name: "my_event", params: ["a": 123])
```

I'm only implemented very basic feature set that fits my needs at this point. Will extend this package as I have the need for it, but contributions are very welcome.
