
import Foundation

/// Configuration for a `Dependency`.
public struct DependencyConfiguration {
    let threadSleepNanoseconds:UInt64
    
    /// Initialises a configuration for a `Dependency`
    /// - Parameters:
    ///   - threadSleepNanoseconds: The number of nanoseconds that task waits between checking whether or not the `Dependency` is still attempting a refresh.
    public init(threadSleepNanoSeconds: UInt64) {
        self.threadSleepNanoseconds = threadSleepNanoSeconds
    }
    
    public static let `default`:Self = .init(
        threadSleepNanoSeconds: 100_000_000
    )
    
}
