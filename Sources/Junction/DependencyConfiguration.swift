
import Foundation

/// Configuration for a `Dependency`.
public struct DependencyConfiguration {
    internal var threadSleepNanoSeconds:UInt64
    internal var defaultTaskTimeout:TimeInterval
    internal var maximumRefreshes:Int
    
    /// Initialises a configuration for a `Dependency`
    /// - Parameters:
    ///   - threadSleepNanoSeconds: The number of nanoseconds that task waits between checking whether or not the `Dependency` is still attempting a refresh.
    ///   - defaultTaskTimeout: The number of seconds that passes till a task will timeout. It's not guaranteed that the task will throw an error at the exact timeout, but even if the task succeeds, but succeeds after the timeout a timeout error will be thrown. The timeout error is a `DependencyError` with `.code` = `.timeout`
    ///   - maximumRefreshes: The maximum number of times a dependency will refresh and retry before failing. The error thrown is a `DependencyError` with `.code` = `.maximumRefreshesReached`
    public init(threadSleepNanoSeconds: UInt64, defaultTaskTimeout: TimeInterval, maximumRefreshes: Int) {
        self.threadSleepNanoSeconds = threadSleepNanoSeconds
        self.defaultTaskTimeout = defaultTaskTimeout
        self.maximumRefreshes = maximumRefreshes
    }
    
    public static let `default`:Self = .init(
        threadSleepNanoSeconds: 100_000_000,
        defaultTaskTimeout: 10,
        maximumRefreshes: 4
    )
}
