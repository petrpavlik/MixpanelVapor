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

public struct MixpanelConfiguration {
    public var projectId: String
    public var authorization: BasicAuthorization
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

        private var client: Mixpanel {
            guard let configuration else {
                fatalError("MixpanelVapor not configured. Use app.vapor.configuration = ...")
            }
            
            // This should not be necessary.
            return .init(client: request?.client ?? application.client,
                         logger: request?.logger ?? application.logger,
                         configuration: configuration)
        }
        
        public func track(name: String, params: [String: any Content] = [:]) async {
            await client.track(name: name, params: params)
        }
    }
}

public extension Request {
    var mixpanel: Application.MixpanelClient {
        .init(application: application, request: self)
    }
}

