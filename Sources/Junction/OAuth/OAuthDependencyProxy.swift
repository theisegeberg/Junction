
public protocol OAuthDependencyProxy<Success, RefreshToken, AccessToken> {
    associatedtype Success
    associatedtype RefreshToken
    associatedtype AccessToken
    func run(_ accessToken: AccessToken) async -> TaskResult<Success>
    func refreshAccessToken(_ refreshToken: RefreshToken) async -> RefreshResult<AccessToken>
    func refreshRefreshToken() async -> RefreshResult<RefreshToken>
}
