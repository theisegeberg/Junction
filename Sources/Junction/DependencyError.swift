
import Foundation

public struct DependencyError: LocalizedError {
    public enum ErrorCode {
        /// Request timed out
        case timeout
        /// Dependency failed to refresh
        case failedRefresh
    }

    public let code: ErrorCode
    public var errorDescription: String {
        switch code {
        case .timeout:
            return "Request timed out"
        case .failedRefresh:
            return "Refresh of dependency failed"
        }
    }

    public init(code: ErrorCode) {
        self.code = code
    }
}
