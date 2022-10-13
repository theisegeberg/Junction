
struct TwoStepRunner<OuterDependency, InnerDependency> {
    let outerRunner: DependentRunner<OuterDependency>
    let innerRunner: DependentRunner<InnerDependency>

    init() {
        outerRunner = .init()
        innerRunner = .init()
    }

    func run<Success>(
        _ runBlock: (InnerDependency) async -> TaskResult<Success>,
        updateInner: (OuterDependency) async -> RefreshResult<InnerDependency>,
        updateOuter: () async -> RefreshResult<OuterDependency>
    ) async -> RunResult<Success> {
        await outerRunner.run {
            refreshDependency in
            let innerResult = await innerRunner.run {
                accessDependency in
                await runBlock(accessDependency)
            } updateDependency: {
                await updateInner(refreshDependency)
            }
            if case .failedRefresh = innerResult {
                return .dependencyRequiresRefresh
            }
            return .success(innerResult)
        } updateDependency: {
            let result = await updateOuter()
            await innerRunner.reset()
            return result
        }
        .flatMap { $0 }
    }
}
