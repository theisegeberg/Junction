
public protocol OAuthRunnerContext<Success, RefreshToken, AccessToken> {
    associatedtype Success
    associatedtype RefreshToken
    associatedtype AccessToken
    func run(_ accessToken: AccessToken) async -> TaskResult<Success>
    func updateAccessToken(_ refreshToken: RefreshToken) async -> RefreshResult<AccessToken>
    func updateRefreshToken() async -> RefreshResult<RefreshToken>
}
