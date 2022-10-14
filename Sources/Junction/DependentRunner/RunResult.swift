
public enum RunResult<Success> {
    case success(Success)
    case failedRefresh
    case timeout
    case otherError(Error)

    public func map<NewSuccess>(_ f: (Success) -> NewSuccess) -> RunResult<NewSuccess> {
        switch self {
        case let .success(success):
            return .success(f(success))
        case .failedRefresh:
            return .failedRefresh
        case let .otherError(error):
            return .otherError(error)
        case .timeout:
            return .timeout
        }
    }

    public func flatMap<NewSuccess>(_ f: (Success) -> RunResult<NewSuccess>) -> RunResult<NewSuccess> {
        switch self {
        case let .success(success):
            switch f(success) {
            case let .success(success):
                return .success(success)
            case .failedRefresh:
                return .failedRefresh
            case let .otherError(error):
                return .otherError(error)
            case .timeout:
                return .timeout
            }
        case .failedRefresh:
            return .failedRefresh
        case let .otherError(error):
            return .otherError(error)
        case .timeout:
            return .timeout
        }
    }
}

extension RunResult: Equatable where Success: Equatable {
    public static func == (lhs: RunResult<Success>, rhs: RunResult<Success>) -> Bool {
        switch (lhs, rhs) {
        case let (.success(s1), .success(s2)):
            return s1 == s2
        case (.failedRefresh, .failedRefresh):
            return true
        case (.timeout, .timeout):
            return true
        default:
            return false
        }
    }
}
