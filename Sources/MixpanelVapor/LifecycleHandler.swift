import Vapor

final class MixpanelLifecycleHandler: LifecycleHandler {

    private let mixpanel: Mixpanel
    init(mixpanel: Mixpanel) {
        self.mixpanel = mixpanel
    }

    func shutdownAsync(_ application: Application) async {
        await mixpanel.shutdown()
    }
}
