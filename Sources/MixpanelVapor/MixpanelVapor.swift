import NIOCore
import UAParserSwift
import Vapor

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

/// Auth params to configure your Mixpanel instance with
public struct MixpanelConfiguration: Sendable {

    /// your project token
    public var token: String

    /// Allow you to point to mixpanel's EU-based servers, or a mock server. Default value is `https://api.mixpanel.com`.
    public var apiUrl = URL(string: "https://api.mixpanel.com")!

    /// Set to `true` to enable debug logging
    public var isDebug = false

    /// Initializes an instance of the API with the given project token.
    /// - Parameter token: your project token
    public init(token: String) {
        self.token = token
    }
}

final class Mixpanel: Sendable {

    private let eventProcessor: BatchEventProcessor<ContinuousClock>

    private let client: Client
    private let logger: Logger
    private let configuration: MixpanelConfiguration

    private let isDebug: Bool

    var pendingEvents: [Event] {
        get async {
            await eventProcessor.buffer
        }
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

    func flush() async {
        await eventProcessor.flush()
    }

    func shutdown() async {
        await eventProcessor.shutdown()
    }

    init(client: Client, configuration: MixpanelConfiguration) {
        self.client = client
        self.logger = Logger(label: "Mixpanel")
        self.configuration = configuration
        self.isDebug = configuration.isDebug

        eventProcessor = BatchEventProcessor(
            clock: .continuous,
            logger: logger,
            apiUrl: configuration.apiUrl, httpClient: client)

        // logger.info(
        //     "Starting mixpanel event upload every \(threadSafeProperties.defaultUploadInterval) second(s)"
        // )
    }

    // MARK: - Events

    func track(distinctId: String?, name: String, request: Request?, params: [String: any Content])
        async
    {
        var properties: [String: any Content] = [
            "time": Int(Date().timeIntervalSince1970 * 1000),
            "$insert_id": UUID().uuidString,
            "distinct_id": distinctId ?? "",
            "token": configuration.token,
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

        properties["mp_lib"] = Constants.libName
        properties["$lib_version"] = Constants.libVersion

        properties.merge(params) { _, new in
            new
        }

        let event = Event(event: name, properties: properties)
        await eventProcessor.track(event: event)
    }

    // MARK: - People

    func peopleSet(
        distinctId: String, request: Request?, setParams: [String: any Content],
        params: [String: any Content]
    ) async {

        var properties: [String: any Content] = [
            "$distinct_id": distinctId,
            "$token": configuration.token,
            "$ip": "0",  // do not look up the IP by default, would be the IP of the server
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

        properties["mp_lib"] = Constants.libName
        properties["$lib_version"] = Constants.libVersion

        properties["$set"] = setParams.mapValues({ AnyContent($0) })

        properties.merge(params) { _, new in
            new
        }

        do {
            let response = try await client.post(
                URI(string: configuration.apiUrl.absoluteString + "/engage#profile-set")
            ) { req in
                req.headers.contentType = .json
                let encodableProperties: [String: AnyContent] = properties.mapValues({ .init($0) })
                try req.content.encode([encodableProperties])
            }

            if response.status.code >= 400 {
                logger.error(
                    "Failed to post an event to Mixpanel", metadata: ["response": "\(response)"])
            }
        } catch {
            logger.report(error: error)
        }
    }

    func peopleDelete(distinctId: String) async {

        let properties: [String: any Content] = [
            "$distinct_id": distinctId,
            "$token": configuration.token,
            "$delete": "null",
        ]

        do {
            let response = try await client.post(
                URI(string: configuration.apiUrl.absoluteString + "/engage#profile-delete")
            ) { req in
                req.headers.contentType = .json
                let encodableProperties: [String: AnyContent] = properties.mapValues({ .init($0) })
                try req.content.encode([encodableProperties])
            }

            if response.status.code >= 400 {
                logger.error(
                    "Failed to post an event to Mixpanel", metadata: ["response": "\(response)"])
            }
        } catch {
            logger.report(error: error)
        }
    }
}
