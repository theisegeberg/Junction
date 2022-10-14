
import Foundation

public struct TwoStepRunner<OuterDependency, InnerDependency> {
    let outerRunner: DependentRunner<OuterDependency>
    let innerRunner: DependentRunner<InnerDependency>

    public init(outerDependency: OuterDependency? = nil, innerDependency: InnerDependency? = nil, threadSleep: UInt64, defaultTimeout: TimeInterval) {
        outerRunner = .init(dependency: outerDependency, threadSleep: threadSleep, defaultTimeout: defaultTimeout)
        innerRunner = .init(dependency: innerDependency, threadSleep: threadSleep, defaultTimeout: defaultTimeout)
    }

    public func run<Success>(
        _ runBlock: (InnerDependency) async throws -> TaskResult<Success>,
        refreshInner: (OuterDependency) async throws -> RefreshResult<InnerDependency>,
        refreshOuter: (DependentRunner<InnerDependency>) async throws -> RefreshResult<OuterDependency>,
        timeout: TimeInterval? = nil
    ) async -> RunResult<Success> {
        await outerRunner.run {
            refreshDependency in
            let innerResult = await innerRunner.run(
                task: {
                    accessDependency in
                    try await runBlock(accessDependency)
                }, refreshDependency: {
                    try await refreshInner(refreshDependency)
                }, timeout: timeout
            )
            if case .failedRefresh = innerResult {
                return .dependencyRequiresRefresh
            }
            return .success(innerResult)
        } refreshDependency: {
            try await refreshOuter(innerRunner)
        }
        .flatMap { $0 }
    }
}
