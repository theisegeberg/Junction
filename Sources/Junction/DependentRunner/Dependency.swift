
import Foundation

public actor Dependency<DependencyType> {
    
    private class VersionedDependency {
        private var latest: DependencyType?
        private var version: Int
        private var isFailed: Bool

        init(dependency: DependencyType? = nil) {
            latest = dependency
            version = 0
            isFailed = false
        }

        func setDependency(_ dependency: DependencyType?) {
            if version == Int.max {
                version = 0
            }
            isFailed = false
            version = version + 1
            latest = dependency
        }
        
        func getVersion() -> Int {
            version
        }
        
        func getLatest() -> DependencyType? {
            latest
        }
        
        func reset() {
            latest = nil
            version = 0
            isFailed = false
        }
        
        func fail() {
            isFailed = true
        }
        
        func getIsFailed() -> Bool {
            isFailed
        }
    }

    private enum State {
        case ready
        case refreshing
        case failedRefresh
    }

    private var state: State = .ready
    private var dependency: VersionedDependency
    private var threadSleep: UInt64
    private var defaultTimeout: TimeInterval

    /// Creates a new `Dependency`.
    ///
    /// After creating it you can call `.run` to execute code that depends on it.
    ///
    /// - Parameters:
    ///   - dependency: A pre-existing dependency.
    ///   - threadSleep: If the runner is currently refreshing then another incoming task will go into a holding pattern, the `threadSleep` is the intervals at which a holding pattern task will check if the dependency is refreshed. It's given in nano seconds.
    ///   - defaultTimeout: The default number of seconds a task will wait before it times out.
    public init(
        dependency: DependencyType? = nil,
        threadSleep: UInt64 = 100_000_000,
        defaultTimeout: TimeInterval = 10
    ) {
        self.dependency = VersionedDependency(dependency: dependency)
        self.threadSleep = threadSleep
        self.defaultTimeout = defaultTimeout
    }

    /// Execute the code provided by the context.
    /// - Parameter context: A context that provides information for running and generating dependencies.
    /// - Returns: The result of the execution.
    public func run<Success>(
        _ proxy: any DependencyProxy<Success, DependencyType>
    ) async throws -> RunResult<Success> {
        try await run(task: proxy.run, refreshDependency: proxy.refresh, timeout: proxy.timeout())
    }

    /// Tries to execute a tas that requires a `Dependency`. If the `Dependency` is invalid or missing it
    /// attempt to run
    /// - Parameters:
    ///   - task: The job to be performed. Must return a `TaskResult` which can either mean that it succeded, threw an error or requires an update
    ///   - updateDependency: The job to be performed if the dependency is missing or needs to be refreshed. Must return a `RefreshResult` which can be a succesful refresh or an error.
    ///   - timeout: The maximum time the task must wait before it times out. It will only timeout once it restarts.
    /// - Returns: The final result of the run after any refreshes, timeouts and successes.
    public func run<Success>(
        task: (_ dependency: DependencyType) async throws -> (TaskResult<Success>),
        refreshDependency: (DependencyType?) async throws -> (RefreshResult<DependencyType>),
        timeout: TimeInterval? = nil
    ) async throws -> RunResult<Success> {
        try await run(task: task, refreshDependency: refreshDependency, started: .init(), timeout: timeout)
    }

    private func run<Success>(
        task: (_ dependency: DependencyType) async throws -> (TaskResult<Success>),
        refreshDependency: (DependencyType?) async throws -> (RefreshResult<DependencyType>),
        started: Date,
        timeout: TimeInterval?
    ) async throws -> RunResult<Success> {
        while state == .refreshing {
            try await Task.sleep(nanoseconds: threadSleep)
            await Task.yield()
            if Date().timeIntervalSince(started) > (timeout ?? defaultTimeout) {
                return .timeout
            }
        }

        guard isNotTimedOut(started: started, timeout: timeout) else {
            return .timeout
        }

        if state == .failedRefresh {
            return .failedRefresh
        }

        if dependency.getIsFailed() || dependency.getLatest() == nil {
            state = .refreshing
            switch try await refreshDependency(dependency.getLatest()) {
                case let .refreshedDependency(refreshed):
                    dependency.setDependency(refreshed)
                    state = .ready
                    return try await run(
                        task: task,
                        refreshDependency: refreshDependency,
                        started: started,
                        timeout: timeout
                    )
                case .failedRefresh:
                    state = .failedRefresh
                    return .failedRefresh
            }
        }
        
        guard let actualDependency = dependency.getLatest() else {
            dependency.fail()
            return try await run(
                task: task,
                refreshDependency: refreshDependency,
                started: started,
                timeout: timeout
            )
        }
        
        let versionAtRun = dependency.getVersion()
        switch try await task(actualDependency) {
            case .dependencyRequiresRefresh:
                /// If  the is the same that means that no other process changed the dependency
                /// while we were performing our task. If the lock changed then another process
                /// changed it, and we should just move on.
                if versionAtRun == dependency.getVersion() {
                    dependency.fail()
                }
                return try await run(
                    task: task,
                    refreshDependency: refreshDependency,
                    started: started,
                    timeout: timeout
                )
            case let .success(success):
                return .success(success)
        }
    }
    
    /// Resets the current runner dependencies.
    public func reset() async throws {
        while state == .refreshing {
            try await Task.sleep(nanoseconds: threadSleep)
            await Task.yield()
        }
        dependency.reset()
        state = .ready
    }
    
    /// Manually refreshes the dependency from without. Wil
    /// - Parameter freshDependency: The new dependency.
    public func refresh(dependency freshDependency: DependencyType) async throws {
        while state == .refreshing {
            try await Task.sleep(nanoseconds: threadSleep)
            await Task.yield()
        }
        dependency.setDependency(freshDependency)
        state = .ready
    }

    private func isNotTimedOut(started: Date, timeout: TimeInterval?) -> Bool {
        Date().timeIntervalSince(started) < (timeout ?? defaultTimeout)
    }
}
