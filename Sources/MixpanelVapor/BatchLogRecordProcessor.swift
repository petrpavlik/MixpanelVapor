import AsyncAlgorithms
import DequeModule
import Logging

struct BatchEventProcessorConfiguration: Sendable {
    /// The maximum queue size.
    ///
    /// - Warning: After this size is reached log will be dropped.
    var maximumQueueSize: UInt = 2000

    /// The maximum delay between two consecutive log exports.
    var scheduleDelay: Duration = .seconds(1)

    /// The maximum batch size of each export.
    ///
    /// - Note: If the queue reaches this size, a batch will be exported even if ``scheduleDelay`` has not elapsed.
    var maximumExportBatchSize: UInt = 512

    /// The duration a single export can run until it is cancelled.
    var exportTimeout: Duration = .seconds(30)
}

actor BatchEventProcessor<Clock: _Concurrency.Clock> where Clock.Duration == Duration {

    private let configuration: BatchEventProcessorConfiguration
    private let clock: Clock
    private let logger = Logger(label: "OTelBatchLogRecordProcessor")
    private let explicitTickStream: AsyncStream<Void>
    private let explicitTick: AsyncStream<Void>.Continuation
    internal /* for testing */ private(set) var buffer: Deque<Mixpanel.Event>

    private var isShuttingDown = false
    private var timerTask: Task<Void, any Error>?

    init(configuration: BatchEventProcessorConfiguration, clock: Clock) {
        // self.exporter = exporter
        self.configuration = configuration
        self.clock = clock

        buffer = Deque(minimumCapacity: Int(configuration.maximumQueueSize))
        (explicitTickStream, explicitTick) = AsyncStream.makeStream()
    }

    func start() async {

        guard timerTask == nil else {
            logger.warning("Batch log processor already started.")
            return
        }

        timerTask = Task {
            let timerSequence = AsyncTimerSequence(interval: configuration.scheduleDelay, clock: clock).map { _ in }
            for try await _ in timerSequence {
                await self.tick()
            }
        }
    }

    func track(event: Mixpanel.Event) {

        if isShuttingDown {
            logger.warning("Batch log processor is shutting down. Dropping log \(event.event).")
            return
        }

        buffer.append(event)

        if buffer.count == configuration.maximumQueueSize {
            explicitTick.yield()
        }
    }

    func flush() async {
        await tick()
    }

    private func tick() async {

    }

    func shutdown() async {
        timerTask?.cancel()
        isShuttingDown = true
        await flush()
    }
}

extension BatchEventProcessor where Clock == ContinuousClock {
    /// Create a batch log processor exporting log batches via the given log exporter.
    ///
    /// - Parameters:
    ///   - exporter: The log exporter to receive batched logs to export.
    ///   - configuration: Further configuration parameters to tweak the batching behavior.
    init(configuration: BatchEventProcessorConfiguration) {
        self.init(configuration: configuration, clock: .continuous)
    }
}
