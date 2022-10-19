
import Foundation

/// Error that can be returned by running a `Dependency`
///
/// In the case where multiple situations have arisen simultaneously, for instance a task may be timed out while it has also failed a refresh the order of checks is as follows: critical error, failed refresh and then timeout. The reason for this is that a critical error has the intention of informing other tasks that this has occured.
///
public struct DependencyError: LocalizedError, Equatable {
    public enum ErrorCode: Equatable {
        public static func == (lhs: DependencyError.ErrorCode, rhs: DependencyError.ErrorCode) -> Bool {
            switch (lhs, rhs) {
            case (.timeout, .timeout),
                    (.failedRefresh, .failedRefresh),
                    (.critical, .critical):
                return true
            default:
                return false
            }
        }

        /// Request timed out
        case timeout
        /// Dependency failed to refresh
        case failedRefresh
        /// Critical error, this will end all other tasks performed by this `Dependency` as well. The task that throws this error will have `wasThrownByThisTask` set to true, other tasks will return false. It is not guaranteed that calls can not return after this has occured. But once it has occured a check will occur before attempting the next call.
        case critical(wasThrownByThisTask: Bool, error: Error?)
    }

    public let code: ErrorCode
    
    public init(code: ErrorCode) {
        self.code = code
    }
}
