import Atomics
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
    private let isDebug: Bool

    private var numRunningUploads = 0

    private let pendingAddEventTasksCounter = ManagedAtomic<Int>(0)

    init(clock: Clock, logger: Logger, apiUrl: URL, httpClient: Client, isDebug: Bool) {
        // self.exporter = exporter
        self.clock = clock
        self.httpClient = httpClient
        self.uploadInterval = self.defaultUploadInterval
        self.apiUrl = apiUrl
        self.logger = logger
        self.isDebug = isDebug

        buffer = Array()  // TODO: use a better data structure for this

        Task { [weak self] in
            await self?.start()
        }
    }

    private func start() async {

        if isDebug {
            logger.debug("Starting to upload events every \(defaultUploadInterval) second(s)")
        }

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
        pendingAddEventTasksCounter.wrappingIncrement(ordering: .relaxed)
        Task {
            await add(event: event)
            pendingAddEventTasksCounter.wrappingDecrement(ordering: .relaxed)
        }
    }

    private func add(event: Mixpanel.Event) async {
        if isDebug {
            logger.debug("Adding event to the buffer- \(event.event)")
        }
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

        var numYielded = 0
        let maxYields = 5

        // track() is a nonisolated function that internally schedules a task to add the event to the buffer on this actor
        // this is a workaround to let the task finish before flushing.
        //
        // In case there's some obscure client logic that keeps adding events one after another, we give up after 5 yields
        // to avoid getting stuck.
        while pendingAddEventTasksCounter.load(ordering: .relaxed) > 0 && numYielded < maxYields {
            if isDebug {
                logger.debug(
                    "Waiting for \(pendingAddEventTasksCounter.load(ordering: .relaxed)) events to be added to the buffer"
                )
            }
            await Task.yield()
            numYielded += 1

            if numYielded >= maxYields {
                logger.error("Timed out waiting for events to be added to the buffer")
                break
            }
        }

        if isDebug {
            logger.debug("Manually flushin \(buffer.count) events")
        }
        await tick()
    }

    private func tick() async {

        numRunningUploads += 1
        defer {
            numRunningUploads -= 1
        }

        guard !buffer.isEmpty else {

            if isDebug {
                logger.debug("No events to upload. Scheduling next tick.")
            }

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

            if isDebug {
                logger.debug("Successfully uploaded \(eventsToSend.count) events")
            }

            // success, reset the interval and schedule next upload
            uploadInterval = defaultUploadInterval
            scheduleNextTick()

        } catch {

            if isDebug {
                logger.debug("Failed to upload events. Retrying in \(uploadInterval) second(s)")
            }

            // return the events and try again
            self.buffer.insert(contentsOf: buffer, at: 0)
            // increase the interval to avoid spamming the server and schedule next upload
            uploadInterval = min(maxUploadInterval, uploadInterval * 2)
            scheduleNextTick()
        }
    }

    func shutdown() async {

        if isDebug {
            if buffer.isEmpty {
                logger.debug("Shutting down batch log processor")
            } else {
                logger.debug("Shutting down batch log processor. Flushing \(buffer.count) events.")
            }
        }

        timerTask?.cancel()
        isShuttingDown = true
        await flush()

        while numRunningUploads > 0 {
            if isDebug {
                logger.debug("Waiting for \(numRunningUploads) uploads to finish")
            }
            do {
                try await Task.sleep(for: .milliseconds(10))
            } catch {
                logger.error("Failed to finish all uploads \(error)")
            }
        }

        if isDebug {
            logger.debug("All uploads finished.")
        }
    }
}
