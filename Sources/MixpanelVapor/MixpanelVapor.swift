//
//  File.swift
//
//
//  Created by Petr Pavlik on 27.12.2022.
//

import Foundation
import Vapor

private struct AnyContent: Content {

    private let _encode: (Encoder) throws -> Void
    public init<T: Encodable>(_ wrapped: T) {
        _encode = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
    
    init(from decoder: Decoder) throws {
        fatalError("we don't need this")
    }
}

/// Auth params to configure your Mixpanel instance with
public struct MixpanelConfiguration {
    
    /// The project id you with to be logging events to.
    public var projectId: String
    
    /// Username and password of the service account you with to use to authenticate.
    public var authorization: BasicAuthorization
    
    /// Initializer
    /// - Parameters:
    ///   - projectId: The project id you with to be logging events to.
    ///   - authorization: Username and password of the service account you with to use to authenticate.
    public init(projectId: String, authorization: BasicAuthorization) {
        self.projectId = projectId
        self.authorization = authorization
    }
}

final class Mixpanel {
    
    private let client: Client
    private let logger: Logger
    private let apiUrl = "https://api.mixpanel.com"
    private let configuration: MixpanelConfiguration
    
    init(client: Client, logger: Logger, configuration: MixpanelConfiguration) {
        self.client = client
        self.logger = logger
        self.configuration = configuration
    }
    
    func track(name: String, params: [String: any Content]) async {
        
        var properties: [String: any Content] = [
            "time": Int(Date().timeIntervalSince1970 * 1000),
            "$insert_id": UUID().uuidString,
            "distinct_id": ""
        ]
        
        properties.merge(params) { current, _ in
            current
        }
        
        struct Event: Content {
            var event: String
            var properties: [String: AnyContent]
            
            init(event: String, properties: [String: any Content]) {
                self.event = event
                self.properties = properties.mapValues({ value in
                    AnyContent(value)
                })
            }
        }
        
        let event = Event(event: name, properties: properties)
                
        do {
            let response = try await client.post(URI(string: apiUrl + "/import?strict=1&project_id=\(configuration.projectId)")) { req in
                                
                req.headers.basicAuthorization = configuration.authorization

                req.headers.contentType = .json
                
                try req.content.encode([event])
            }
            
            if response.status.code >= 400 {
                logger.error("Failed to post an event to Mixpanel", metadata: ["response": "\(response)"])
            }
        } catch {
            logger.report(error: error)
        }
    }
}

public extension Application {
    
    /// Access mixpanel
    ///
    /// You can also use `request.mixpanel` when logging within a route handler.
    var mixpanel: MixpanelClient {
        .init(application: self, request: nil)
    }

    struct MixpanelClient {
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
        ///   - name: The name of the event
        ///   - params: Optional custom params assigned to the event
        public func track(name: String, params: [String: any Content] = [:]) async {
            await client?.track(name: name, params: params)
        }
    }
}

public extension Request {
    /// Access mixpanel
    var mixpanel: Application.MixpanelClient {
        .init(application: application, request: self)
    }
}

