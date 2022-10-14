
import Foundation

public actor DependentRunner<Dependency> {
    private class VersionedDependency {
        var latest: Dependency?
        var version: Int

        init(dependency: Dependency? = nil) {
            latest = dependency
            version = 0
        }

        func setDependency(_ dependency: Dependency?) {
            if version == Int.max {
                version = 0
            }
            version = version + 1
            latest = dependency
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

    /// Creates a new runner.
    /// - Parameters:
    ///   - dependency: A pre-existing dependency.
    ///   - threadSleep: If the runner is currently refreshing then another incoming task will go into a holding pattern, the `threadSleep` is the intervals at which a holding pattern task will check if the dependency is refreshed. It's given in nano seconds.
    ///   - defaultTimeout: The default number of seconds a task will wait before it times out.
    public init(
        dependency: Dependency? = nil,
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
        _ context: any DependentRunnerContext<Success, Dependency>
    ) async -> RunResult<Success> {
        await run(task: context.run, refreshDependency: context.refresh, timeout: context.timeout())
    }

    /// Tries to execute a tas that requires a `Dependency`. If the `Dependency` is invalid or missing it
    /// attempt to run
    /// - Parameters:
    ///   - task: The job to be performed. Must return a `TaskResult` which can either mean that it succeded, threw an error or requires an update
    ///   - updateDependency: The job to be performed if the dependency is missing or needs to be refreshed. Must return a `RefreshResult` which can be a succesful refresh or an error.
    ///   - timeout: The maximum time the task must wait before it times out. It will only timeout once it restarts.
    /// - Returns: The final result of the run after any refreshes, timeouts and successes.
    public func run<Success>(
        task: (_ dependency: Dependency) async throws -> (TaskResult<Success>),
        refreshDependency: () async throws -> (RefreshResult<Dependency>),
        timeout: TimeInterval? = nil
    ) async -> RunResult<Success> {
        await run(task: task, refreshDependency: refreshDependency, started: .init(), timeout: timeout)
    }

    private func run<Success>(
        task: (_ dependency: Dependency) async throws -> (TaskResult<Success>),
        refreshDependency: () async throws -> (RefreshResult<Dependency>),
        started: Date,
        timeout: TimeInterval?
    ) async -> RunResult<Success> {
        while state == .refreshing {
            do {
                try await Task.sleep(nanoseconds: threadSleep)
            } catch {
                return .otherError(error)
            }
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

        guard let actualDependency = dependency.latest else {
            do {
                state = .refreshing
                switch try await refreshDependency() {
                case let .refreshedDependency(refreshed):
                    dependency.setDependency(refreshed)
                    state = .ready
                    return await run(
                        task: task,
                        refreshDependency: refreshDependency,
                        started: started,
                        timeout: timeout
                    )
                case .failedRefresh:
                    state = .failedRefresh
                    return .failedRefresh
                }
            } catch {
                return .otherError(error)
            }
        }

        do {
            let versionAtRun = dependency.version
            switch try await task(actualDependency) {
            case .dependencyRequiresRefresh:
                /// If  the is the same that means that no other process changed the dependency
                /// while we were performing our task. If the lock changed then another process
                /// changed it, and we should just move on.
                if versionAtRun == dependency.version {
                    dependency.setDependency(nil)
                }
                return await run(
                    task: task,
                    refreshDependency: refreshDependency,
                    started: started,
                    timeout: timeout
                )
            case let .success(success):
                return .success(success)
            }
        } catch {
            return .otherError(error)
        }
    }

    public func reset() async throws {
        while state == .refreshing {
            try await Task.sleep(nanoseconds: threadSleep)
            await Task.yield()
        }
        dependency.version = 0
        dependency.latest = nil
        state = .ready
    }

    public func refresh(dependency freshDependency: Dependency) async throws {
        while state == .refreshing {
            try await Task.sleep(nanoseconds: threadSleep)
            await Task.yield()
        }
        dependency.latest = freshDependency
        state = .ready
    }

    private func isNotTimedOut(started: Date, timeout: TimeInterval?) -> Bool {
        Date().timeIntervalSince(started) < (timeout ?? defaultTimeout)
    }
}
