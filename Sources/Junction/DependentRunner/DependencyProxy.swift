
import Foundation

public protocol DependencyProxy<Success, Value> {
    associatedtype Success
    associatedtype Value
    func run(_ dependency: Value) async throws -> (TaskResult<Success>)
    func refresh(failingDependency:Value?) async throws -> (RefreshResult<Value>)
    func timeout() -> TimeInterval?
}
