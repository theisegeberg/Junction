//
//  ReRunner.swift
//  DepInversionTest
//
//  Created by Theis Egeberg on 09/10/2022.
//

import Foundation

public enum TaskResult<Success> {
    case success(Success)
    case dependencyRequiresRefresh
}

public enum RefreshResult<Dependency> {
    case refreshedDependency(Dependency)
    case failedRefresh
}

public enum RunResult<Success> {
    case success(Success)
    case failedRefresh
    case timeout
    case otherError(Error)
    
    public func map<NewSuccess>(_ f:(Success) -> NewSuccess) -> RunResult<NewSuccess> {
        switch self {
            case .success(let success):
                return .success(f(success))
            case .failedRefresh:
                return .failedRefresh
            case .otherError(let error):
                return .otherError(error)
            case .timeout:
                return .timeout
        }
    }
    
    public func flatMap<NewSuccess>(_ f:(Success) -> RunResult<NewSuccess>) -> RunResult<NewSuccess> {
        switch self {
            case .success(let success):
                switch f(success) {
                    case .success(let success):
                        return .success(success)
                    case .failedRefresh:
                        return .failedRefresh
                    case .otherError(let error):
                        return .otherError(error)
                    case .timeout:
                        return .timeout
                }
            case .failedRefresh:
                return .failedRefresh
            case .otherError(let error):
                return .otherError(error)
            case .timeout:
                return .timeout

        }
    }
    
}

public actor DependentRunner<Dependency> {
    
    private var lockActive:Bool = false
    private var currentLock:Int = 0
    private var refreshFailed:Bool = false
    private var dependency:Dependency?
    private var threadSleep:UInt64
    private var defaultTimeout:TimeInterval
    
    public init(
        dependency:Dependency? = nil,
        threadSleep:UInt64 = 100_000_000,
        defaultTimeout:TimeInterval = 10
    ) {
        self.dependency = dependency
        self.threadSleep = threadSleep
        self.defaultTimeout = defaultTimeout
    }
    
    public func reset() {
        lockActive = false
        currentLock = 0
        refreshFailed = false
        dependency = nil
    }
    
    public func run<Success>(
        task:(_ dependency:Dependency) async throws -> (TaskResult<Success>),
        updateDependency:() async throws -> (RefreshResult<Dependency>),
        started:Date = .init(),
        timeout:TimeInterval? = nil
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
            self.lockActive = true
            if self.currentLock == Int.max { self.currentLock = 0 }
            self.currentLock = self.currentLock + 1
            do {
                switch try await updateDependency() {
                    case .refreshedDependency(let updatedDepency):
                        self.dependency = updatedDepency
                        self.lockActive = false
                        return await run(
                            task: task,
                            updateDependency: updateDependency,
                            started: started,
                            timeout: timeout
                        )
                    case .failedRefresh:
                        self.refreshFailed = true
                        return .failedRefresh
                }
            } catch {
                return .otherError(error)
            }
        }
        
        do {
            let lockAtRun = self.currentLock
            switch try await task(dependency) {
                case .dependencyRequiresRefresh:
                    if lockAtRun == currentLock {
                        self.dependency = nil
                    }
                    return await run(
                        task: task,
                        updateDependency: updateDependency,
                        started: started,
                        timeout: timeout
                    )
                case .success(let success):
                    return .success(success)
            }
        } catch {
            return .otherError(error)
        }
        
    }
    
}
