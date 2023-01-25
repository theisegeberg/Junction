
import Foundation

/// An `actor` that handles both providing and creating a dependency. It can handle many asynchronous
/// tasks  that all depend upon one shared dependency. If that value becomes invalid then a single refresh
/// will be attempted while all the tasks are put in a holding pattern. Once the dependency has been
/// refreshed all the tasks will be retried.
public actor Dependency<DependencyType: Sendable> {
    
    private enum State {
        case ready
        case refreshing
        case failedRefresh
        case criticalError(Error?)
        
        var isRefreshsing:Bool {
            if case .refreshing = self {
                return true
            } else {
                return false
            }
        }
        
    }

    private var state: State = .ready
    private var refreshCount: Int = 0
    private var store: VersionStore<DependencyType>
    private var configuration:DependencyConfiguration

    /// Creates a new `Dependency`.
    ///
    /// After creating it you can call `.run` to execute code that depends on it.
    ///
    /// - Parameter configuration: Configuration of the dependency, defaults to a `.default`
    /// version. See `DependencyConfiguration` for more details.
    public init(
        configuration: DependencyConfiguration
    ) {
        store = VersionStore(dependency: nil)
        self.configuration = configuration
    }

    /// This will run a dependency inside of this one.
    /// - Parameters:
    ///   - dependency: The inner dependency to run.
    ///   - task: The task that must be run, which requires a dependency. This dependency relies on
    ///   another dependency.
    ///   - innerRefresh: The task that will work to refresh the innermost dependency.
    ///   - outerRefresh: The task that will work to refresh the outermost dependency.
    ///   - timeout: The timeout for the task.
    /// - Returns: The `Success` result of the task.
    public func mapRun<InnerDependency: Sendable, Success: Sendable>(
        dependency: Dependency<InnerDependency>,
        task: @Sendable (_ outer:DependencyType, _ inner:InnerDependency, _ context:RefreshContext) async throws -> TaskResult<Success>,
        innerRefresh: @Sendable (_ outer:DependencyType, _ inner:InnerDependency?, _ context:RefreshContext) async throws -> (RefreshResult<InnerDependency>),
        outerRefresh: @Sendable (_ dependency:Dependency<InnerDependency>, _ outer:DependencyType?, _ context:RefreshContext) async throws -> (RefreshResult<DependencyType>)
    ) async throws -> Success {
        try await run(
            task: {
                outerDependency, context -> TaskResult<Success> in
                do {
                    return try await .success(
                        dependency
                            .run(
                                task: { innerDependency, context -> TaskResult<Success> in
                                    try await task(outerDependency, innerDependency, context)
                                },
                                refresh: { innerDependency, context in
                                    try await innerRefresh(outerDependency, innerDependency, context)
                                }
                            )
                    )
                } catch let error as DependencyError where error.code == .failedRefresh {
                    return .dependencyRequiresRefresh
                }
            },
            refresh: {
                outerDependency, context in
                try await outerRefresh(dependency, outerDependency, context)
            }
        )
    }

    func run<Success>(
        task: @Sendable (_ dependency:DependencyType, _ context:RefreshContext) async throws -> (TaskResult<Success>),
        refresh: @Sendable (_ dependency:DependencyType?, _ context:RefreshContext) async throws -> (RefreshResult<DependencyType>)
    ) async throws -> Success {
        try await run(task: task, refresh: refresh, started: .init())
    }
    
    /// The private implementation of run. The main difference is that this one doesn't set the started time.
    /// This is the entrance method of all runs, and contains the pseudo state machine that handles the
    /// running.
    private func run<Success>(
        task: @Sendable (_ dependency:DependencyType, _ context:RefreshContext) async throws -> (TaskResult<Success>),
        refresh: @Sendable (_ dependency:DependencyType?, _ context:RefreshContext) async throws -> (RefreshResult<DependencyType>),
        started: Date
    ) async throws -> Success {
        try await Task.sleep(while: state.isRefreshsing, nanoseconds: configuration.threadSleepNanoseconds)
        try validateTaskState()

        guard let actualDependency = store.getLatest(),
              case .ready = state,
              store.getIsValid()
        else {
            state = .refreshing
            refreshCount = refreshCount + 1
            try validateTaskState()
            
            switch try await refresh(
                store.getLatest(),
                RefreshContext(
                    repeatedRefreshCount: refreshCount,
                    time: Date().timeIntervalSince(started)
                )
            ) {
            case let .refreshedDependency(refreshed):
                store.newVersion(refreshed)
                state = .ready
                return try await run(
                    task: task,
                    refresh: refresh,
                    started: started
                )
            case .failedRefresh:
                state = .failedRefresh
                throw DependencyError(code: .failedRefresh)
            }
        }

        let versionAtRun = store.getVersion()
        let taskResult = try await task(
            actualDependency,
            RefreshContext(
                repeatedRefreshCount: refreshCount,
                time: Date().timeIntervalSince(started)
            )
        )
        try validateTaskState()
        switch taskResult {
        case let .success(success):
            refreshCount = 0 // On a succesful run we'll reset the refreshCount to zero.
            return success
        case .dependencyRequiresRefresh:
            /// Race condition check:
            /// If  the is the same that means that no other process changed the dependency
            /// while we were performing our task. If the lock changed then another process
            /// changed it, and we should just move on.
            if versionAtRun == store.getVersion() {
                store.invalidate()
            }
            return try await run(
                task: task,
                refresh: refresh,
                started: started
            )
        case let .criticalError(underlyingError: error):
            state = .criticalError(error)
            throw DependencyError(
                code: .critical(
                    wasThrownByThisTask: true,
                    error: error)
            )
        }
    }

    /// Resets the dependency. If a refresh is running, the reset will occur after the refresh.
    public func reset() async throws {
        try await Task.sleep(while: state.isRefreshsing, nanoseconds: configuration.threadSleepNanoseconds)
        store.reset()
        state = .ready
        refreshCount = 0
    }

    /// Manually refreshes the dependency from without.
    /// - Parameter freshDependency: The new dependency.
    public func refresh(dependency freshDependency: DependencyType) async throws {
        try await Task.sleep(while: state.isRefreshsing, nanoseconds: configuration.threadSleepNanoseconds)
        store.newVersion(freshDependency)
        refreshCount = 0
        state = .ready
    }

    private func validateTaskState() throws {
        switch state {
        case .failedRefresh:
            throw DependencyError(code: .failedRefresh)
        case let .criticalError(error):
            throw DependencyError(code: .critical(wasThrownByThisTask: false, error: error))
        case .refreshing, .ready:
            break
        }
        try Task.checkCancellation()
    }

}
