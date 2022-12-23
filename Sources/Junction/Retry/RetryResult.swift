import Foundation

public enum RetryResult<Success> {
    case success(Success)
    case retry
}