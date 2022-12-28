# MixpanelVapor

MixpanelVapor is a library for tracking events to Mixpanel from your Vapor server-side Swift applications.

## Initialization
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
