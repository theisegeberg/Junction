
public protocol OAuthDependencyProxy<Success, RefreshToken, AccessToken> {
    associatedtype Success
    associatedtype RefreshToken
    associatedtype AccessToken
    func run(_ accessToken: AccessToken) async -> TaskResult<Success>
    func refreshAccessToken(_ refreshToken: RefreshToken, failedAccessToken:AccessToken?) async -> RefreshResult<AccessToken>
    func refreshRefreshToken(failedRefreshToken:RefreshToken?) async -> RefreshResult<RefreshToken>
}
