//
//  File.swift
//
//
//  Created by Petr Pavlik on 01.05.2024.
//

import Vapor

extension Application {

    /// Access mixpanel
    ///
    /// You can also use `request.mixpanel` when logging within a route handler.
    public var mixpanel: MixpanelClient {
        .init(application: self)
    }

    public struct MixpanelClient: Sendable {
        let application: Application

        struct ClientKey: StorageKey {
            typealias Value = Mixpanel
        }

        struct ConfigurationKey: StorageKey {
            typealias Value = MixpanelConfiguration
        }

        public var configuration: MixpanelConfiguration? {
            get {
                self.application.storage[ConfigurationKey.self]
            }
            nonmutating set {
                self.application.storage[ConfigurationKey.self] = newValue
            }
        }

        var client: Mixpanel? {

            if let client = self.application.storage[ClientKey.self] {
                return client
            }

            guard let configuration else {
                (application.logger).warning(
                    "MixpanelVapor not configured. Use app.mixpanel.configuration = ...")
                return nil
            }

            let client = Mixpanel(
                client: application.client,
                configuration: configuration)
            application.storage[ClientKey.self] = client
            application.lifecycle.use(MixpanelLifecycleHandler(mixpanel: client))
            application.logger.debug("Mixpanel client initialized")
            return client
        }

        /// Track an event to mixpanel. This scheudles the event to be uploaded in the background. Use `await flush()` to manually trigger upload.
        /// - Parameters:
        ///   - distinctId: Identifier of the user who triggered this event. Pass `nil` or an empty string to track an event that does not belong to any user.
        ///   - name: The name of the event
        ///   - request: You can optionally pass request to automatically parse the ip address and user-agent header
        ///   - params: Optional custom params assigned to the event
        public func track(
            distinctId: String? = nil, name: String, request: Request? = nil,
            params: [String: MixpanelProperty] = [:]
        ) {
            client?.track(
                distinctId: distinctId, name: name, request: request, params: params)
        }

        /// Set properties on an user record in engage
        /// - Parameters:
        ///   - distinctId: Represents user id
        ///   - request: Passing a request automatically populates properties parsed from request headers, such as the operating system or the IP address for geocoding.
        ///   - setParams: user properties
        ///   - params: Can be used to to set properties such as `$ip`.
        public func peopleSet(
            distinctId: String, request: Request? = nil, setParams: [String: MixpanelProperty],
            params: [String: MixpanelProperty] = [:]
        ) async {
            await client?.peopleSet(
                distinctId: distinctId, request: request, setParams: setParams, params: params)
        }

        /// Delete an user record in engage
        /// - Parameter distinctId: User id
        public func peopleDelete(distinctId: String) async {
            await client?.peopleDelete(distinctId: distinctId)
        }

        /// Manually trigger upload of app events
        ///
        /// App events are automatically uploaded every second.
        public func flush() async {
            await client?.flush()
        }

        /// Blocks the shutdown process until all pending events are uploaded. Triggers a flush if there's any pending events.
        ///
        /// > Warning: This method is deprecated and does nothing.
        /// >
        /// > Shutting down is now handled automatically by the lifecycle handler.
        /// > You no longer need to call this method during application shutdown.
        @available(
            *, deprecated, message: "This is now handled automatically by the lifecycle handler"
        )
        public func shutdown() async {
            // This is now handled by the lifecycle handler and this method is a no-op and deprecated
        }
    }
}
