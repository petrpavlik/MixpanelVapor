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

    /// Initializes an instance of the API with the given project token.
    /// - Parameter token: your project token
    public init(token: String) {
        self.token = token
    }
}

final class Mixpanel: Sendable {

    private let client: Client
    private let logger: Logger
    private let configuration: MixpanelConfiguration

    let threadSafeProperties: ThereadSaveProperties

    private let eventLoopGroup: EventLoopGroup
    private let isDebug: Bool = true

    var pendingEvents: [Event] {
        get async {
            await threadSafeProperties.pendingEvents
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

    actor ThereadSaveProperties {
        private(set) var pendingEvents: [Event] = []
        private(set) var numRunningEventUploads = 0
        private(set) var isShuttingDown = false
        private(set) var uploadInterval: TimeInterval = 1
        private(set) var scheduledFlush: Scheduled<()>?

        let maxUploadInterval: TimeInterval = 60
        let defaultUploadInterval: TimeInterval = 1

        private let logger: Logger
        private let isDebug: Bool

        init(logger: Logger, isDebug: Bool) {
            self.logger = logger
            self.isDebug = isDebug
        }

        func schedule(event: Event) {
            pendingEvents.append(event)
        }

        func getEventForUpload() -> [Event] {

            if pendingEvents.count > 2_000 {
                // TODO: be smarter about this
                logger.warning(
                    "Mixpanel: too many events in the queue, dropping \(pendingEvents.count - 2_000) events"
                )
                pendingEvents.removeFirst(pendingEvents.count - 2_000)
            }

            let events = pendingEvents
            pendingEvents = []
            return events
        }

        func returnFailedEvents(events: [Event]) {
            pendingEvents.insert(contentsOf: events, at: 0)
        }

        func increaseRunningEventUploads() {
            numRunningEventUploads += 1
            if isDebug {
                logger.debug("increased running event uploads to \(numRunningEventUploads)")
            }
        }

        func decreaseRunningEventUploads() {
            numRunningEventUploads -= 1
            if isDebug {
                logger.debug("decreased running event uploads to \(numRunningEventUploads)")
            }
        }

        func markShuttingDown() {
            isShuttingDown = true
        }

        func resetUploadInterval() {
            uploadInterval = defaultUploadInterval
        }

        func increaseUploadInterval() {
            uploadInterval = min(maxUploadInterval, uploadInterval * 2)
        }

        func scheduleFlush(eventLoopGroup: EventLoopGroup, trigger: @escaping @Sendable () -> Void)
            async
        {

            guard isShuttingDown == false else {
                return
            }

            scheduledFlush?.cancel()
            scheduledFlush = nil

            scheduledFlush = eventLoopGroup.next().scheduleTask(
                in: .milliseconds(Int64(uploadInterval * 1_000))
            ) {
                trigger()
            }
        }

        func cancelScheduledFlush() {
            scheduledFlush?.cancel()
            scheduledFlush = nil
        }
    }

    func flush() async {

        let events = await threadSafeProperties.getEventForUpload()

        guard events.isEmpty == false else {
            return
        }

        if isDebug {
            logger.debug("flushing \(events.count) events")
        }

        await threadSafeProperties.cancelScheduledFlush()

        await threadSafeProperties.increaseRunningEventUploads()

        do {
            try await upload(events: events)
            await threadSafeProperties.resetUploadInterval()
        } catch {
            await threadSafeProperties.returnFailedEvents(events: events)
            await threadSafeProperties.increaseUploadInterval()
            logger.report(error: error)
        }

        await threadSafeProperties.decreaseRunningEventUploads()

        if await threadSafeProperties.isShuttingDown == false {
            await scheduleFlush()
        }
    }

    func shutdown() async {

        await threadSafeProperties.markShuttingDown()

        await flush()

        let numRunningEventUploads = await threadSafeProperties.numRunningEventUploads
        if numRunningEventUploads > 0 {
            logger.info(
                "waiting for \(numRunningEventUploads) event upload jobs to finish"
            )
            do {
                while true {
                    let count = await threadSafeProperties.numRunningEventUploads
                    if count <= 0 {
                        break
                    }
                    if isDebug {
                        logger.debug("waiting for \(count) event upload jobs to finish")
                    }
                    try await Task.sleep(for: .milliseconds(10))
                }
                logger.info("all event upload jobs finished")
            } catch {
                logger.error("shutdown cancelled due to error: \(error)")
            }

        }
    }

    private func upload(events: [Event]) async throws {
        logger.debug("uploading \(events.count) events")
        let response = try await client.post(
            URI(string: configuration.apiUrl.absoluteString + "/track")
        ) { req in
            req.headers.contentType = .json

            try req.content.encode(events)
        }

        if response.status.code >= 400 {

            var responseBody = response.body
            let readableBytes = responseBody?.readableBytes ?? 0
            let body = responseBody?.readString(length: readableBytes)

            logger.error(
                "Failed to post an events to Mixpanel",
                metadata: ["status_code": "\(response.status)", "response_body": "\(body ?? "")"])
        }

        // Do not retry 4xx responses outside of 429, they'd just be rejected again
        if response.status.code == 429 {
            throw Abort(.tooManyRequests)
        } else if response.status.code >= 500 {
            throw Abort(.internalServerError)
        }
    }

    private func scheduleFlush() async {

        await threadSafeProperties.scheduleFlush(eventLoopGroup: eventLoopGroup) { [weak self] in
            Task { [weak self] in
                await self?.flush()
            }
        }
    }

    init(client: Client, eventLoopGroup: EventLoopGroup, configuration: MixpanelConfiguration) {
        self.client = client
        self.logger = Logger(label: "Mixpanel")
        self.eventLoopGroup = eventLoopGroup
        self.configuration = configuration
        self.threadSafeProperties = ThereadSaveProperties(logger: logger, isDebug: true)

        logger.info(
            "Starting mixpanel event upload every \(threadSafeProperties.defaultUploadInterval) second(s)"
        )
        Task { [weak self] in
            await self?.scheduleFlush()
        }
    }

    // MARK: - Events

    func track(distinctId: String?, name: String, request: Request?, params: [String: any Content])
        async
    {

        guard await threadSafeProperties.isShuttingDown == false else {
            logger.warning("Mixpanel is shutting down, rejecting event `\(name)`")
            return
        }

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
        await threadSafeProperties.schedule(event: event)
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
