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
    case otherError(Error)
    
    public func map<T>(_ f:(Output) -> T) -> RunResult<T> {
        switch self {
            case .output(let output):
                return .output(f(output))
            case .updateFailed:
                return .updateFailed
            case .otherError(let error):
                return .otherError(error)
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
                }
            case .updateFailed:
                return .updateFailed
            case .otherError(let error):
                return .otherError(error)
        }
    }
    
}

public protocol Resettable {
    func reset() async
}

public actor DependentRunner<Dependency>:Resettable {
    
    var lockActive:Bool = false
    var currentLock:Int = 0
    var updateFailed:Bool = false
    var dependency:Dependency?
    
    public init(dependency:Dependency? = nil) {
        self.dependency = dependency
    }
    
    public func reset() {
        lockActive = false
        currentLock = 0
        updateFailed = false
        dependency = nil
    }
    
    public func run<Output>(
        childRunner:(any Resettable)? = nil,
        task:(_ dependency:Dependency) async throws -> (TaskResult<Output>),
        updateDependency:() async throws -> (UpdateResult<Dependency>)
    ) async -> RunResult<Output> {
        
        while lockActive {
            if let stallResult:RunResult<Output> = await stall() {
                return stallResult
            }
        }
        
        // No dependency present
        guard let dependency else {
            return await update(
                childRunner: childRunner,
                task: task,
                updateDependency: updateDependency
            )
        }
        
        return await runWithDependency(
            dependency: dependency,
            childRunner: childRunner,
            task: task,
            updateDependency: updateDependency
        )
        
    }
    
    func stall<Output>() async -> RunResult<Output>? {
        do {
            try await Task.sleep(nanoseconds: 50_000_000)
        } catch {
            return .otherError(error)
        }
        await Task.yield()
        if updateFailed {
            return .updateFailed
        }
        return nil
    }
    
    /// Missing dependency
    func update<Output>(
        childRunner:(any Resettable)? = nil,
        task:(_ dependency:Dependency) async throws -> (TaskResult<Output>),
        updateDependency:() async throws -> (UpdateResult<Dependency>)
    ) async -> RunResult<Output> {
        self.lockActive = true
        if self.currentLock == Int.max { self.currentLock = 0 }
        self.currentLock = self.currentLock + 1
        do {
            switch try await updateDependency() {
                case .updatedDependency(let updatedDepency):
                    await childRunner?.reset() // Reset the child runner because the outer dependency is now cleared
                    self.dependency = updatedDepency
                    self.lockActive = false
                    return await run(
                        childRunner: childRunner,
                        task: task,
                        updateDependency: updateDependency
                    )
                case .updateFailed:
                    self.updateFailed = true
                    return .updateFailed
            }
        } catch {
            return .otherError(error)
        }
    }
    
    /// Dependency exist
    func runWithDependency<Output>(
        dependency:Dependency,
        childRunner:(any Resettable)? = nil,
        task:(_ dependency:Dependency) async throws -> (TaskResult<Output>),
        updateDependency:() async throws -> (UpdateResult<Dependency>)
    ) async -> RunResult<Output> {
        do {
            let lockAtRun = self.currentLock
            switch try await task(dependency) {
                case .badDependency:
                    if lockAtRun == currentLock {
                        self.dependency = nil
                    }
                    return await run(childRunner: childRunner, task: task, updateDependency: updateDependency)
                case .output(let output):
                    return .output(output)
            }
        } catch {
            return .otherError(error)
        }
    }
    
}
