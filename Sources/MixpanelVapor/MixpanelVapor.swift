//
//  File.swift
//
//
//  Created by Petr Pavlik on 27.12.2022.
//

import Foundation
import Vapor
import UAParserSwift

/// Auth params to configure your Mixpanel instance with
public struct MixpanelConfiguration {

    /// your project token
    public var token: String
    
    /// Allow you to point to mixpanel's EU-based servers, or a mock server. Default value is `https://api.mixpanel.com`.
    public var apiUrl = URL(string: "https://api.mixpanel.com")!
    
    /// Initializes an instance of the API with the given project token.
    /// - Parameter token: your project token
    public init(token: String) {
        self.token = token
    }
}

final class Mixpanel {
    
    private let client: Client
    private let logger: Logger
    private let configuration: MixpanelConfiguration
    
    init(client: Client, logger: Logger, configuration: MixpanelConfiguration) {
        self.client = client
        self.logger = logger
        self.configuration = configuration
    }
        
    func track(distinctId: String?, name: String, request: Request?, params: [String: any Content]) async {
        
        var properties: [String: any Content] = [
            "time": Int(Date().timeIntervalSince1970 * 1000),
            "$insert_id": UUID().uuidString,
            "distinct_id": distinctId ?? "",
            "token": configuration.token
        ]
        
        if let request {
            // https://docs.mixpanel.com/docs/tracking/how-tos/effective-server-side-tracking
            
            if let ip = request.peerAddress?.ipAddress {
                properties["ip"] = ip
            }
            
            if let userAgentHeader = request.headers[.userAgent].first {
                let parser = UAParser(agent: userAgentHeader)
                
                if let browser = parser.browser?.name {
                    properties["$browser"] = browser
                }
                
                if let device = parser.device?.vendor {
                    properties["$device"] = device
                }
                
                if let os = parser.os?.name {
                    properties["$os"] = os
                }
            }
        }
        
        properties.merge(params) { _ , new in
            new
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
            let response = try await client.post(URI(string: configuration.apiUrl.absoluteString + "/track")) { req in
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
    
    func peopleSet(distinctId: String, request: Request?, setParams: [String: any Content], params: [String: any Content]) async {
        
        var properties: [String: any Content] = [
            "$distinct_id": distinctId,
            "$token": configuration.token,
            "$ip": "0" // do not look up the IP by default, would be the IP of the server
        ]
        
        var setParams = setParams
        
        if let request {
            // https://docs.mixpanel.com/docs/tracking/how-tos/effective-server-side-tracking
            
            if let ip = request.peerAddress?.ipAddress {
                properties["$ip"] = ip
            }
            
            if let userAgentHeader = request.headers[.userAgent].first {
                let parser = UAParser(agent: userAgentHeader)
                
                if let browser = parser.browser?.name, setParams["$browser"] == nil {
                    setParams["$browser"] = browser
                }
                
                if let device = parser.device?.vendor, setParams["$device"] == nil {
                    setParams["$device"] = device
                }
                
                if let os = parser.os?.name, setParams["$os"] == nil {
                    setParams["$os"] = os
                }
            }
        }
        
        properties["$set"] = setParams.mapValues({ AnyContent($0) })
        
        properties.merge(params) { _ , new in
            new
        }
        
        do {
            let response = try await client.post(URI(string: configuration.apiUrl.absoluteString + "/engage#profile-set")) { req in
                req.headers.contentType = .json
                let encodableProperties: [String: AnyContent] = properties.mapValues({ .init($0) })
                try req.content.encode([encodableProperties])
            }
            
            if response.status.code >= 400 {
                logger.error("Failed to post an event to Mixpanel", metadata: ["response": "\(response)"])
            }
        } catch {
            logger.report(error: error)
        }
    }
    
    func peopleDelete(distinctId: String) async {
        
        let properties: [String: any Content] = [
            "$distinct_id": distinctId,
            "$token": configuration.token,
            "$delete": "null"
        ]

        do {
            let response = try await client.post(URI(string: configuration.apiUrl.absoluteString + "/engage#profile-delete")) { req in
                req.headers.contentType = .json
                let encodableProperties: [String: AnyContent] = properties.mapValues({ .init($0) })
                try req.content.encode([encodableProperties])
            }
            
            if response.status.code >= 400 {
                logger.error("Failed to post an event to Mixpanel", metadata: ["response": "\(response)"])
            }
        } catch {
            logger.report(error: error)
        }
    }
}
