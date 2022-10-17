
import Foundation

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
        /// Critical error, this will end all other tasks performed by this `Dependency` as well. The task that throws this error will have `wasThrownByThisTask` set to true, other false.
        case critical(wasThrownByThisTask: Bool, error: Error?)
    }

    public let code: ErrorCode
    
    public init(code: ErrorCode) {
        self.code = code
    }
}
