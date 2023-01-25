
import Foundation

/// Carries information about what's going on outside of the code being executed.
public struct RefreshContext {
    /// The number of refreshes that has occurred. This will be reset to zero once a success occurs. This
    /// is only meant to count the "loops" where a task requires a refresh and the refresh succeeds but then
    /// the task requires a refresh again.
    public let repeatedRefreshCount:Int
    /// Number of seconds since the task was started.
    public let time:TimeInterval
}
