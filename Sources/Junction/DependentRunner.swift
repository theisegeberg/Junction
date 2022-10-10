//
//  ReRunner.swift
//  DepInversionTest
//
//  Created by Theis Egeberg on 09/10/2022.
//

import Foundation


public enum TaskResult<Output> {
    case output(Output)
    case badDependency
}

public enum UpdateResult<Dependency> {
    case updatedDependency(Dependency)
    case updateFailed
}

public enum RunResult<Output> {
    case output(Output)
    case updateFailed
    case timeout
    case otherError(Error)
    
    public func map<T>(_ f:(Output) -> T) -> RunResult<T> {
        switch self {
            case .output(let output):
                return .output(f(output))
            case .updateFailed:
                return .updateFailed
            case .otherError(let error):
                return .otherError(error)
            case .timeout:
                return .timeout
        }
    }
    
    public func flatMap<T>(_ f:(Output) -> RunResult<T>) -> RunResult<T> {
        switch self {
            case .output(let output):
                switch f(output) {
                    case .output(let output):
                        return .output(output)
                    case .updateFailed:
                        return .updateFailed
                    case .otherError(let error):
                        return .otherError(error)
                    case .timeout:
                        return .timeout
                }
            case .updateFailed:
                return .updateFailed
            case .otherError(let error):
                return .otherError(error)
            case .timeout:
                return .timeout

        }
    }
    
}

public protocol ResettableRunner {
    func reset() async
}

public actor DependentRunner<Dependency>:ResettableRunner {
    
    private var lockActive:Bool = false
    private var currentLock:Int = 0
    private var updateFailed:Bool = false
    private var dependency:Dependency?
    private var threadSleep:UInt64
    private var timeout:TimeInterval
    
    public init(dependency:Dependency? = nil, threadSleep:UInt64 = 100_000_000, timeout:TimeInterval = 10) {
        self.dependency = dependency
        self.threadSleep = threadSleep
        self.timeout = timeout
    }
    
    public func reset() {
        lockActive = false
        currentLock = 0
        updateFailed = false
        dependency = nil
    }
    
    public func run<Output>(
        childRunner:(any ResettableRunner)? = nil,
        task:(_ dependency:Dependency) async throws -> (TaskResult<Output>),
        updateDependency:() async throws -> (UpdateResult<Dependency>),
        started:Date = .init()
    ) async -> RunResult<Output> {
        
        while lockActive {
            if let stallResult:RunResult<Output> = await stall() {
                return stallResult
            }
            if Date().timeIntervalSince(started) > timeout {
                return .timeout
            }
        }
        
        
        
        guard let dependency else {
            return await update(
                childRunner: childRunner,
                task: task,
                updateDependency: updateDependency,
                started: started
            )
        }
        
        return await runWithDependency(
            dependency: dependency,
            childRunner: childRunner,
            task: task,
            updateDependency: updateDependency,
            started: started
        )
        
    }
    
    private func stall<Output>() async -> RunResult<Output>? {
        do {
            try await Task.sleep(nanoseconds: threadSleep)
        } catch {
            return .otherError(error)
        }
        await Task.yield()
        if updateFailed {
            return .updateFailed
        }
        return nil
    }
    
    private func update<Output>(
        childRunner:(any ResettableRunner)? = nil,
        task:(_ dependency:Dependency) async throws -> (TaskResult<Output>),
        updateDependency:() async throws -> (UpdateResult<Dependency>),
        started: Date
    ) async -> RunResult<Output> {
        self.lockActive = true
        if self.currentLock == Int.max { self.currentLock = 0 }
        self.currentLock = self.currentLock + 1
        do {
            switch try await updateDependency() {
                case .updatedDependency(let updatedDepency):
                    await childRunner?.reset()
                    self.dependency = updatedDepency
                    self.lockActive = false
                    return await run(
                        childRunner: childRunner,
                        task: task,
                        updateDependency: updateDependency,
                        started: started
                    )
                case .updateFailed:
                    self.updateFailed = true
                    return .updateFailed
            }
        } catch {
            return .otherError(error)
        }
    }
    
    private func runWithDependency<Output>(
        dependency:Dependency,
        childRunner:(any ResettableRunner)? = nil,
        task:(_ dependency:Dependency) async throws -> (TaskResult<Output>),
        updateDependency:() async throws -> (UpdateResult<Dependency>),
        started: Date
    ) async -> RunResult<Output> {
        do {
            let lockAtRun = self.currentLock
            switch try await task(dependency) {
                case .badDependency:
                    if lockAtRun == currentLock {
                        self.dependency = nil
                    }
                    return await run(
                        childRunner: childRunner,
                        task: task,
                        updateDependency: updateDependency,
                        started: started
                    )
                case .output(let output):
                    return .output(output)
            }
        } catch {
            return .otherError(error)
        }
    }
    
}
