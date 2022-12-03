
import Foundation

/// Configuration for a `Dependency`.
public struct DependencyConfiguration {
    internal var threadSleepNanoSeconds:UInt64
    internal var defaultTaskTimeout:TimeInterval
    internal var maximumRefreshes:Int
    
    /// Initialises a configuration for a `Dependency`
    /// - Parameters:
    ///   - threadSleepNanoSeconds: The number of nanoseconds that task waits between checking whether or not the `Dependency` is still attempting a refresh. Default value is 100.000.000 nano seconds.
    ///   - defaultTaskTimeout: The number of seconds that passes till a task will timeout. It's not guaranteed that the task will throw an error at the exact timeout, but even if the task succeeds, but succeeds after the timeout a timeout error will be thrown. The timeout error is a `DependencyError` with `.code` = `.timeout`. Default value is 10 seconds.
    ///   - maximumRefreshes: The maximum number of times a dependency will refresh and retry before failing. The error thrown is a `DependencyError` with `.code` = `.maximumRefreshesReached`. Default value is 4.
    public init(threadSleepNanoSeconds: UInt64, defaultTaskTimeout: TimeInterval, maximumRefreshes: Int) {
        self.threadSleepNanoSeconds = threadSleepNanoSeconds
        self.defaultTaskTimeout = defaultTaskTimeout
        self.maximumRefreshes = maximumRefreshes
    }
    
    /// This is the default setting running at a long thread sleep, an infinite task timeout.
    public static let `default`:Self = .init(
        threadSleepNanoSeconds: 100_000_000,
        defaultTaskTimeout: 10,
        maximumRefreshes: 10
    )
    
    /// This will sleep indefinitely and rely on the timeout of the underlying code. If a refresh fails it'll fail
    /// immediately. This is useful for such things as HTTP requests.
    public static let recommended:Self = .init(
        threadSleepNanoSeconds: 250_000_000,
        defaultTaskTimeout: .infinity,
        maximumRefreshes: 1
    )
}
