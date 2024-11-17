//
//  File.swift
//  
//
//  Created by Petr Pavlik on 01.05.2024.
//

import Vapor

public extension Application {
    
    /// Access mixpanel
    ///
    /// You can also use `request.mixpanel` when logging within a route handler.
    var mixpanel: MixpanelClient {
        .init(application: self, request: nil)
    }

    struct MixpanelClient: Sendable {
        let application: Application
        let request: Request?

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

        private var client: Mixpanel? {
            guard let configuration else {
                (request?.logger ?? application.logger).error("MixpanelVapor not configured. Use app.mixpanel.configuration = ...")
                return nil
            }
            
            // This should not be necessary.
            return .init(client: request?.client ?? application.client,
                         logger: request?.logger ?? application.logger,
                         configuration: configuration)
        }
        
        /// Track an event to mixpanel
        /// - Parameters:
        ///   - distinctId: Identifier of the user who triggered this event. Pass `nil` or an empty string to track an event that does not belong to any user.
        ///   - name: The name of the event
        ///   - request: You can optionally pass request to automatically parse the ip address and user-agent header
        ///   - params: Optional custom params assigned to the event
        public func track(distinctId: String?, name: String, request: Request? = nil, params: [String: any Content] = [:]) async {
            await client?.track(distinctId: distinctId, name: name, request: request, params: params)
        }
        
        /// Set properties on an user record in engage
        /// - Parameters:
        ///   - distinctId: Represents user id
        ///   - request: Passing a request automatically populates properties parsed from request headers, such as the operating system or the IP address for geocoding.
        ///   - setParams: user properties
        ///   - params: Can be used to to set properties such as `$ip`.
        public func peopleSet(distinctId: String, request: Request? = nil, setParams: [String: any Content], params: [String: any Content] = [:]) async {
            await client?.peopleSet(distinctId: distinctId, request: request, setParams: setParams, params: params)
        }
        
        /// Delete an user record in engage
        /// - Parameter distinctId: User id
        public func peopleDelete(distinctId: String) async {
            await client?.peopleDelete(distinctId: distinctId)
        }
    }
}
