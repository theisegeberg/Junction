
import Foundation

public struct TwoStepRunner<OuterDependency, InnerDependency> {
    let outerRunner: DependentRunner<OuterDependency>
    let innerRunner: DependentRunner<InnerDependency>

    public init(threadSleep: UInt64, timeout: TimeInterval) {
        outerRunner = .init(threadSleep: threadSleep, defaultTimeout: timeout)
        innerRunner = .init(threadSleep: threadSleep, defaultTimeout: timeout)
    }

    public func run<Success>(
        _ runBlock: (InnerDependency) async throws -> TaskResult<Success>,
        refreshInner: (OuterDependency) async throws -> RefreshResult<InnerDependency>,
        refreshOuter: (DependentRunner<InnerDependency>) async throws -> RefreshResult<OuterDependency>
    ) async -> RunResult<Success> {
        await outerRunner.run {
            refreshDependency in
            let innerResult = await innerRunner.run {
                accessDependency in
                try await runBlock(accessDependency)
            } refreshDependency: {
                try await refreshInner(refreshDependency)
            }
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
