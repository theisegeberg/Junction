
import Foundation

public protocol DependentRunnerContext<Success, Dependency> {
    associatedtype Success
    associatedtype Dependency
    func run(_ dependency: Dependency) async throws -> (TaskResult<Success>)
    func refresh() async throws -> (RefreshResult<Dependency>)
    func timeout() -> TimeInterval?
}
