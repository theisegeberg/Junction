
import Foundation

/// TODO
/// currentLock becomes a version count for the dependency
/// locked, failed and open becomes state

public actor DependentRunner<Dependency> {
    
    private class VersionedDependency {
        var latest:Dependency?
        var version:Int
        
        init(dependency: Dependency? = nil) {
            self.latest = dependency
            self.version = 0
        }
        
        func setDependency(_ dependency:Dependency?) {
            if self.version == Int.max {
                self.version = 0
            }
            self.version = version + 1
            self.latest = dependency
        }
    }
    
    private enum State {
        case ready
        case refreshing
        case failedRefresh
    }
    
    private var state:State = .ready
    private var dependency: VersionedDependency
    private var threadSleep: UInt64
    private var defaultTimeout: TimeInterval

    public init(
        dependency: Dependency? = nil,
        threadSleep: UInt64 = 100_000_000,
        defaultTimeout: TimeInterval = 10
    ) {
        self.dependency = VersionedDependency(dependency: dependency)
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

        if state == .failedRefresh {
            return .failedRefresh
        }

        guard let actualDependency = dependency.latest else {
            state = .refreshing
            do {
                switch try await updateDependency() {
                case let .refreshedDependency(refreshed):
                    if state == .refreshing {
                        self.dependency.setDependency(refreshed)
                    }
                    state = .ready
                    return await run(
                        task: task,
                        updateDependency: updateDependency,
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
                    self.dependency.setDependency(nil)
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
        dependency.version = 0
        dependency.latest = nil
        state = .ready
    }

    public func refresh(dependency freshDependency: Dependency) {
        dependency.latest = freshDependency
        state = .ready
    }

}
