
/// A value representing the result of a task. It can be either a succesful task or a situation where the underlying
/// dependency must be refreshed. If you need to exit out in other ways of a task you need to throw an error.
public enum TaskResult<Success> {
    /// Succesful task containing the result.
    case success(Success)
    /// The used dependency requires a refresh, performed by `Dependency`
    case dependencyRequiresRefresh
}
