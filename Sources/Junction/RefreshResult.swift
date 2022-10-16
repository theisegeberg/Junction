
/// The result of a refresh. It can be either a succesful refresh: `.refreshedDependency(Dependency)`
/// or a `.failedRefresh` in case it wasn't possible.
public enum RefreshResult<DependencyType> {
    /// A succesfully refreshed dependency.
    case refreshedDependency(DependencyType)
    /// A failed refresh.
    case failedRefresh
}
