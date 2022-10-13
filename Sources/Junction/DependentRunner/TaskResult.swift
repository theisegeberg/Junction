
public enum TaskResult<Success> {
    case success(Success)
    case dependencyRequiresRefresh
}
