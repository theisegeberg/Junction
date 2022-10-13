
import Foundation

public actor DependentRunner<Dependency> {
    private var lockActive: Bool = false
    private var currentLock: Int = 0
    private var refreshFailed: Bool = false
    private var dependency: Dependency?
    private var threadSleep: UInt64
    private var defaultTimeout: TimeInterval

    public init(
        dependency: Dependency? = nil,
        threadSleep: UInt64 = 100_000_000,
        defaultTimeout: TimeInterval = 10
    ) {
        self.dependency = dependency
        self.threadSleep = threadSleep
        self.defaultTimeout = defaultTimeout
    }

    public func run<Success>(
        _ context: any DependentRunnerContext<Success, Dependency>
    ) async -> RunResult<Success> {
        await run(task: context.run, updateDependency: context.refresh, timeout: context.timeout())
    }

    public func run<Success>(
        task: (_ dependency: Dependency) async throws -> (TaskResult<Success>),
        updateDependency: () async throws -> (RefreshResult<Dependency>),
        timeout: TimeInterval? = nil
    ) async -> RunResult<Success> {
        await run(task: task, updateDependency: updateDependency, started: .init(), timeout: timeout)
    }

    private func run<Success>(
        task: (_ dependency: Dependency) async throws -> (TaskResult<Success>),
        updateDependency: () async throws -> (RefreshResult<Dependency>),
        started: Date,
        timeout: TimeInterval?
    ) async -> RunResult<Success> {
        while lockActive {
            do {
                try await Task.sleep(nanoseconds: threadSleep)
            } catch {
                return .otherError(error)
            }
            await Task.yield()
            if refreshFailed {
                return .failedRefresh
            }
            if Date().timeIntervalSince(started) > (timeout ?? defaultTimeout) {
                return .timeout
            }
        }

        guard let dependency else {
            lockActive = true
            incrementLock()
            do {
                switch try await updateDependency() {
                case let .refreshedDependency(updatedDepency):
                    if lockActive == true {
                        // Only update the dependency if the lock is still active.
                        self.dependency = updatedDepency
                    }
                    lockActive = false
                    return await run(
                        task: task,
                        updateDependency: updateDependency,
                        started: started,
                        timeout: timeout
                    )
                case .failedRefresh:
                    refreshFailed = true
                    return .failedRefresh
                }
            } catch {
                return .otherError(error)
            }
        }

        do {
            let lockAtRun = currentLock
            switch try await task(dependency) {
            case .dependencyRequiresRefresh:
                /// If  the is the same that means that no other process changed the dependency
                /// while we were performing our task. If the lock changed then another process
                /// changed it, and we should just move on.
                if lockAtRun == currentLock {
                    self.dependency = nil
                }
                return await run(
                    task: task,
                    updateDependency: updateDependency,
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

    public func reset() {
        currentLock = 0
        dependency = nil
        refreshFailed = false
        lockActive = false
    }

    public func refresh(dependency freshDependency: Dependency) {
        incrementLock()
        refreshFailed = false
        dependency = freshDependency
        lockActive = false
    }

    func incrementLock() {
        if currentLock == Int.max { currentLock = 0 }
        currentLock = currentLock + 1
    }
}
