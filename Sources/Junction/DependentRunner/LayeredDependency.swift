
import Foundation

/// Dependency which has two layers.
///
/// This means that you can attempt to run `B -> C`, but if `B` is missing then it will try to create that by running `A -> B`, and if `A` is missing it will try to create `A` by running `Void -> A`.
///
/// These concepts are encapsulated in the terms `OuterDependency` and `InnerDependency`.
public struct LayeredDependency<OuterDependency, InnerDependency> {
    let outerRunner: Dependency<OuterDependency>
    let innerRunner: Dependency<InnerDependency>

    public init(outerDependency: OuterDependency? = nil, innerDependency: InnerDependency? = nil, threadSleep: UInt64, defaultTimeout: TimeInterval) {
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
        _ runBlock: (InnerDependency) async throws -> TaskResult<Success>,
        refreshInner: (OuterDependency) async throws -> RefreshResult<InnerDependency>,
        refreshOuter: (Dependency<InnerDependency>) async throws -> RefreshResult<OuterDependency>,
        timeout: TimeInterval? = nil
    ) async throws -> RunResult<Success> {
        try await outerRunner.run {
            refreshDependency in
            let innerResult = try await innerRunner.run(
                task: {
                    accessDependency in
                    try await runBlock(accessDependency)
                }, refreshDependency: { _ in
                    try await refreshInner(refreshDependency)
                }, timeout: timeout
            )
            if case .failedRefresh = innerResult {
                return .dependencyRequiresRefresh
            }
            return .success(innerResult)
        } refreshDependency: { _ in
            try await refreshOuter(innerRunner)
        }
        .flatMap { $0 }
    }
}
