
import Foundation

/// Dependency which has two layers.
///
/// This means that you can attempt to run `B -> C`, but if `B` is missing then it will try to create that by running `A -> B`, and if `A` is missing it will try to create `A` by running `Void -> A`.
///
/// These concepts are encapsulated in the terms `OuterDependency` and `InnerDependency`.
public struct LayeredDependency<OuterDependencyType, InnerDependencyType> {
    let outerRunner: Dependency<OuterDependencyType>
    let innerRunner: Dependency<InnerDependencyType>

    public init(outerDependency: OuterDependencyType? = nil, innerDependency: InnerDependencyType? = nil, threadSleep: UInt64, defaultTimeout: TimeInterval) {
        outerRunner = .init(dependency: outerDependency, threadSleep: threadSleep, defaultTimeout: defaultTimeout)
        innerRunner = .init(dependency: innerDependency, threadSleep: threadSleep, defaultTimeout: defaultTimeout)
    }
    
    /// Runs a task that has a dependency which has another dependency.
    ///
    /// Tries to run `B -> C`, with a closure that can provide `A -> B`, and a closure that can provide `Dependency<B> -> A`.
    ///
    /// The reasoning behind providing the `Dependency<B>` to the closure that provides the outermost dependency (`A`) is that in some cases when creating the outermost dependency the innermost (`B`) is also created .
    ///
    /// - Parameters:
    ///   - runBlock: Closure that takes an `InnerDependency` and provides the actual result. If the dependency is stale this must return: `TaskResult.dependencyRequiresRefresh`.
    ///   - refreshInner: Closure that refreshes the `InnerDependency`, and requires an `OuterDependency` to work
    ///   - refreshOuter: Closure that refreshes the `OuterDependency`
    ///   - timeout: The seconds the task may run before actively cancelling.
    /// - Returns: The result of the `runBlock` wrapped in a `RunResult`
    public func run<Success>(
        _ runBlock: (InnerDependencyType) async throws -> TaskResult<Success>,
        refreshInner: (OuterDependencyType, InnerDependencyType?) async throws -> RefreshResult<InnerDependencyType>,
        refreshOuter: (Dependency<InnerDependencyType>, OuterDependencyType?) async throws -> RefreshResult<OuterDependencyType>,
        timeout: TimeInterval? = nil
    ) async throws -> Success {
        try await outerRunner.run {
            refreshDependency in
            do {
                let result = try await innerRunner.run(
                    task: {
                        accessDependency in
                        try await runBlock(accessDependency)
                    }, refreshDependency: { failedDependency in
                        try await refreshInner(refreshDependency, failedDependency)
                    }, timeout: timeout
                )
                return .success(result)
            } catch let error as DependencyError where error.code == .failedRefresh {
                return .dependencyRequiresRefresh
            }
        } refreshDependency: { failedDependency in
            try await refreshOuter(innerRunner, failedDependency)
        }
        
    }
}
