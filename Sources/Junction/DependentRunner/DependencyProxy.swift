
import Foundation

public protocol DependencyProxy<Success, DependencyType> {
    associatedtype Success
    associatedtype DependencyType
    func run(_ dependency: DependencyType) async throws -> (TaskResult<Success>)
    func refresh(failingDependency:DependencyType?) async throws -> (RefreshResult<DependencyType>)
    func timeout() -> TimeInterval?
}
