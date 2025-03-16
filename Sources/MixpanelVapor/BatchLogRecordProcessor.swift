import AsyncAlgorithms
import Logging
import Vapor

actor BatchEventProcessor<Clock: _Concurrency.Clock> where Clock.Duration == Duration {

    private let clock: Clock
    private let logger: Logger
    internal /* for testing */ private(set) var buffer: [Mixpanel.Event]
    private let httpClient: Client

    private var isShuttingDown = false
    private var timerTask: Task<Void, any Error>?

    private let defaultUploadInterval: TimeInterval = 1
    private let maxUploadInterval: TimeInterval = 60
    private var uploadInterval: TimeInterval

    private let maximumQueueSize: UInt = 2000
    private let maximumExportBatchSize: UInt = 512
    private let apiUrl: URL

    init(clock: Clock, logger: Logger, apiUrl: URL, httpClient: Client) {
        // self.exporter = exporter
        self.clock = clock
        self.httpClient = httpClient
        self.uploadInterval = self.defaultUploadInterval
        self.apiUrl = apiUrl
        self.logger = logger

        buffer = Array() // TODO: use a better data structure for this
    }

    func start() async {

        if isShuttingDown {
            logger.warning("Batch log processor is shutting down")
            return
        }

        guard timerTask == nil else {
            logger.warning("Batch log processor already started.")
            return
        }

        scheduleNextTick()
    }

    private func scheduleNextTick() {
        timerTask?.cancel()

        if isShuttingDown {
            logger.warning("Batch log processor is shutting down.")
            return
        }

        let sleepInterval = uploadInterval
        let clock = self.clock

        timerTask = Task { [weak self] in
            try await Task.sleep(for: .seconds(sleepInterval), clock: clock)
            await self?.tick()
        }
    }

    nonisolated func track(event: Mixpanel.Event) {

        if isShuttingDown {
            logger.warning("Batch log processor is shutting down. Dropping log \(event.event).")
            return
        }

        buffer.append(event)

        if buffer.count == maximumQueueSize {
            await tick()
        }
    }

    func flush() async {
        await tick()
    }

    private func tick() async {

        guard !buffer.isEmpty else {
            scheduleNextTick()
            return
        }

        if buffer.count > maximumExportBatchSize {
            logger.warning(
                "Buffer size exceeds maximum export batch size. Dropping \(buffer.count - Int(maximumExportBatchSize)) oldest events."
            )
        }

        let buffer = self.buffer.reversed().prefix(Int(maximumExportBatchSize))
        self.buffer.removeAll()

        do {

            // We throw only in a case where it makes sense to return the events to the buffer and try again

            let eventsToSend = Array(buffer)
            let logger = self.logger

            let response = try await httpClient.post(
                URI(string: apiUrl.absoluteString + "/track")
            ) { req in
                req.headers.contentType = .json

                do {
                    try req.content.encode(eventsToSend)
                } catch {
                    // There's not point trying this again, the events are lost, log the error and move on
                    logger.error("Failed to encode events to JSON", metadata: ["error": "\(error)"])
                }
            }

            // log the error
            if response.status.code >= 400 {
                var responseBody = response.body
                let readableBytes = responseBody?.readableBytes ?? 0
                let body = responseBody?.readString(length: readableBytes)

                logger.error(
                    "Failed to post an events to Mixpanel",
                    metadata: [
                        "status_code": "\(response.status)", "response_body": "\(body ?? "")",
                    ])
            }

            // Do not retry 4xx responses outside of 429, they'd just be rejected again
            if response.status.code == 429 {
                throw Abort(.tooManyRequests)
            } else if response.status.code >= 500 {
                throw Abort(.internalServerError)
            }

            // success, reset the interval and schedule next upload
            uploadInterval = defaultUploadInterval
            scheduleNextTick()

        } catch {
            // return the events and try again
            self.buffer.insert(contentsOf: buffer, at: 0)
            // increase the interval to avoid spamming the server and schedule next upload
            uploadInterval = min(maxUploadInterval, uploadInterval * 2)
            scheduleNextTick()
        }
    }

    func shutdown() async {
        timerTask?.cancel()
        isShuttingDown = true
        await flush()
    }
}
