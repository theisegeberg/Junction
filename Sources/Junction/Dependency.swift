
import Foundation

/// An `actor` that handles both providing and creating a dependency. It can handle many asyncronous tasks  that all depend upon one shared dependency. If that value becomes invalid then a single refresh will be attemtped while all the tasks are put in a holding pattern. Once the dependency has been refreshed all the tasks will be retried.
///
/// - Warning: This code is complex. That's the nature of both recursive and asynchronous code, and this is both. I've gone to great lengths to make the compiler prove it's functionality. Hence all the generics.
public actor Dependency<DependencyType: Sendable> {
    private enum State {
        case ready
        case refreshing
        case failedRefresh
        case criticalError(Error?)
    }

    private var state: State = .ready
    private var dependency: VersionStore<DependencyType>
    private var threadSleep: UInt64
    private var defaultTimeout: TimeInterval

    /// Creates a new `Dependency`.
    ///
    /// After creating it you can call `.run` to execute code that depends on it.
    ///
    /// - Parameters:
    ///   - dependency: A pre-existing dependency.
    ///   - threadSleep: When a `Dependency` is refreshing, then other tasks will be waiting. While waiting then it will retry periodically with a delay. `threadSleep` is the delay in nano seconds.
    ///   - defaultTimeout: A task that is stuck in a refresh -> retry loop, or is just experiencing slow refreshes will finally timeout. This is not the same as a timeout occured inside the actual task (when performing a task on `URLSession`  for example). This is an extra check placed in the `Dependency` for cases where some given task is too slow.
    public init(
        threadSleep: UInt64 = 100_000_000,
        defaultTimeout: TimeInterval = 10
    ) {
        dependency = VersionStore(dependency: nil)
        self.threadSleep = threadSleep
        self.defaultTimeout = defaultTimeout
    }

    /// Tries to execute a tas kthat requires a `Dependency`. If the `Dependency` is invalid or missing it
    /// attempts to refresh the dependency with the given closure.
    ///
    /// - Throws: A `DependencyError` which can be a timeout or a failure to refresh. If But also rethrows
    /// any error that the `.run` task may throw. Since there are Thread.sleep in the code you may also get
    /// a `CancellationError`.
    ///
    /// - Parameters:
    ///   - task: The job to be performed. Must return a `TaskResult` which can either mean that it succeded or requires an update.
    ///   - refreshDependency: The job to be performed if the dependency is missing or needs to be refreshed. Must return a `RefreshResult` which can be a succesful refresh or an indication that the refresh itself failed. If it fails the entire task `.run` will throw a `DependencyError` with `.code` == `ErrorCode.failedRefresh`.
    ///   - timeout: The maximum time the task must wait before it times out. The timeout check is not guaranteed for tasks, it's not safe to rely on its specific time. Proper usage is as a fail-safe against infinite `try -> refresh -> try` loops.
    /// - Returns: The result of the task in the case where it succeeds.
    public func run<Success: Sendable>(
        task: @Sendable (_ dependency: DependencyType) async throws -> (TaskResult<Success>),
        refreshDependency: @Sendable (DependencyType?) async throws -> (RefreshResult<DependencyType>),
        timeout: TimeInterval? = nil
    ) async throws -> Success {
        try await run(task: task, refreshDependency: refreshDependency, started: .init(), timeout: timeout)
    }

    /// This will run a depedency inside of this one.
    /// - Parameters:
    ///   - dependency: The inner dependency to run.
    ///   - task: The task that must be run, which requires a dependency. This dependency relies on another dependency.
    ///   - innerRefresh: The task that will work to refresh the innermost dependency.
    ///   - outerRefresh: The task that will work to refresh the outermost dependency.
    ///   - timeout: The timeout for the task.
    /// - Returns: The `Success` result of the task.
    public func mapRun<InnerDependency: Sendable, Success: Sendable>(
        dependency: Dependency<InnerDependency>,
        task: @Sendable (DependencyType, InnerDependency) async throws -> TaskResult<Success>,
        innerRefresh: @Sendable (DependencyType, InnerDependency?) async throws -> (RefreshResult<InnerDependency>),
        outerRefresh: @Sendable (Dependency<InnerDependency>, DependencyType?) async throws -> (RefreshResult<DependencyType>),
        timeout: TimeInterval? = nil
    ) async throws -> Success {
        try await run(
            task: {
                outerDependency -> TaskResult<Success> in
                do {
                    return try await .success(
                        dependency
                            .run(
                                task: { innerDependency -> TaskResult<Success> in
                                    try await task(outerDependency, innerDependency)
                                },
                                refreshDependency: { innerDependency in
                                    try await innerRefresh(outerDependency, innerDependency)
                                },
                                timeout: timeout
                            )
                    )
                } catch let error as DependencyError where error.code == .failedRefresh {
                    return .dependencyRequiresRefresh
                }
            },
            refreshDependency: {
                outerDependency in
                try await outerRefresh(dependency, outerDependency)
            },
            timeout: timeout
        )
    }

    /// The private implementation of run. The main difference is that this one doesn't set the started time. This is the entrance method of all runs, and contains the pseudo state machine that handles the running.
    private func run<Success>(
        task: @Sendable (_ dependency: DependencyType) async throws -> (TaskResult<Success>),
        refreshDependency: @Sendable (DependencyType?) async throws -> (RefreshResult<DependencyType>),
        started: Date,
        timeout: TimeInterval?
    ) async throws -> Success {
        try await stall()
        try validateTaskState()
        try validateTaskTimeout(started: started, timeout: timeout)

        guard let actualDependency = dependency.getLatest(),
              case .ready = state,
              dependency.getIsValid()
        else {
            state = .refreshing
            switch try await refreshDependency(dependency.getLatest()) {
            case let .refreshedDependency(refreshed):
                try validateTaskState()
                try validateTaskTimeout(started: started, timeout: timeout)
                dependency.newVersion(refreshed)
                state = .ready
                return try await run(
                    task: task,
                    refreshDependency: refreshDependency,
                    started: started,
                    timeout: timeout
                )
            case .failedRefresh:
                state = .failedRefresh
                throw DependencyError(code: .failedRefresh)
            }
        }

        let versionAtRun = dependency.getVersion()
        let taskResult = try await task(actualDependency)
        try validateTaskState()
        try validateTaskTimeout(started: started, timeout: timeout)
        switch taskResult {
        case let .success(success):
            return success
        case .dependencyRequiresRefresh:
            /// Race condition check:
            /// If  the is the same that means that no other process changed the dependency
            /// while we were performing our task. If the lock changed then another process
            /// changed it, and we should just move on.
            if versionAtRun == dependency.getVersion() {
                dependency.invalidate()
            }
            return try await run(
                task: task,
                refreshDependency: refreshDependency,
                started: started,
                timeout: timeout
            )
        case let .criticalError(underlyingError: error):
            state = .criticalError(error)
            throw DependencyError(code: .critical(wasThrownByThisTask: true, error: error))
        }
    }

    /// Resets the dependency. If a refresh is running, the reset will occur after the refresh.
    public func reset() async throws {
        try await stall()
        dependency.reset()
        state = .ready
    }

    /// Manually refreshes the dependency from without.
    /// - Parameter freshDependency: The new dependency.
    public func refresh(dependency freshDependency: DependencyType) async throws {
        try await stall()
        dependency.newVersion(freshDependency)
        state = .ready
    }

    private func stall() async throws {
        while case .refreshing = state {
            try await Task.sleep(nanoseconds: threadSleep)
            await Task.yield()
        }
    }

    private func validateTaskTimeout(started: Date, timeout: TimeInterval?) throws {
        guard isNotTimedOut(started: started, timeout: timeout) else {
            throw DependencyError(code: .timeout)
        }
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
    }

    private func isNotTimedOut(started: Date, timeout: TimeInterval?) -> Bool {
        Date().timeIntervalSince(started) < (timeout ?? defaultTimeout)
    }
}
