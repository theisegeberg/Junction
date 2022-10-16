
public enum RefreshResult<Dependency> {
    case refreshedDependency(Dependency)
    case failedRefresh
}
