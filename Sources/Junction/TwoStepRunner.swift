
struct TwoStepRunner<OuterDependency, InnerDependency> {
    let outerRunner: DependentRunner<OuterDependency>
    let innerRunner: DependentRunner<InnerDependency>

    init() {
        outerRunner = .init()
        innerRunner = .init()
    }

    func run<Success>(
        _ runBlock: (InnerDependency) async -> TaskResult<Success>,
        refreshInner: (OuterDependency) async -> RefreshResult<InnerDependency>,
        refreshOuter: () async -> RefreshResult<OuterDependency>
    ) async -> RunResult<Success> {
        await outerRunner.run {
            refreshDependency in
            let innerResult = await innerRunner.run {
                accessDependency in
                await runBlock(accessDependency)
            } refreshDependency: {
                await refreshInner(refreshDependency)
            }
            if case .failedRefresh = innerResult {
                return .dependencyRequiresRefresh
            }
            return .success(innerResult)
        } refreshDependency: {
            let result = await refreshOuter()
            await innerRunner.reset()
            return result
        }
        .flatMap { $0 }
    }
}
