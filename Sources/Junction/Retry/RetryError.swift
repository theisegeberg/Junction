import Foundation

public enum RetryError:Error {
    case maximumRetriesReached
    case cancelled
}