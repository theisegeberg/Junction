
public extension Task where Failure == Never, Success == Failure {
    
    /// Inject a dependency into some piece of code that requires it. The dependency may be refreshed,
    /// and information about how many times it was refreshed and how long the task has been stalled
    /// is injected along with the dependency. Refreshes of a `Dependency` will only happen once when
    /// required across all of the users of the `Dependency`.
    ///
    /// - Parameters:
    ///   - dependency: The `Dependency` you're need. It's the intention that this is shared among
    ///   all users of this `Dependency`.
    ///   - task: The code that requires the `Dependency`.
    ///   - refresh: The code that refreshes or creates the underlying value of the `Dependency`.
    /// - Returns: The result of the `task` closure.
    static func inject<Success, DependencyType:Sendable>(
        dependency: Dependency<DependencyType>,
        task: @Sendable (_ dependency:DependencyType, _ context:RefreshContext) async throws -> TaskResult<Success>,
        refresh: @Sendable (_ failedDependency:DependencyType?, _ context:RefreshContext) async throws -> RefreshResult<DependencyType>
    ) async throws -> Success {
        try await dependency.run(task: task, refresh: refresh)
    }
    
}
