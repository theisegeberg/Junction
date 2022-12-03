# TryRefreshRetry
Desperately small and hardened try - refresh - retry library for OAuth and similar scenarios.

---

This small library solves the problem posed OAuth style flows where multiple layers of retrying needs to happen in concert.

In OAuth there is some sort of login that will produce an authorization code. The authorization code can be exchanged for a refresh token. And this refresh token can be used to make short lived access tokens. An access token can be used to access resources from a server.

The solution provided here gives the following benefits:
- If multiple tasks fail all simultaneously, only one refresh will be attempted. This also goes for layered dependencies.
- Option to cascade errors unto sibling tasks if a truly critical problem is observed.
- Multiple dependencies can be nested, with support for the child dependencies being reset when a parent dependency is updated. 
- Completely abstract with no references to OAuth although that is a likely candidate for use.
- Can be placed at either the top: Where the call is being performed closer to the outer edge of the code. Or hidden away at the inner core of the logic that needs to be rerouted. Doesn't provide any framework, just a few concepts that wraps other code.
- Can start from a point of any existing dependencies. Even a complex scenario like having an outer, middle and inner dependency, where only the middle is known in advance, can be resumed.
- Tiny code base that can easily be moved into your project.
- Supports failing on both number of retries and actual time passed timeout.
- 100% Test coverage of all features.
- Backward compatible with macOS 10.15 and iOS 13.
- Forward compatible with Swift 6 concurrency.

---

The test target has a fake OAuth server to test the functionality.

## Example usage

```Swift
let backend = FakeOauth()

let maxTime: UInt64 = 10_000_000_000

let oauthRunner = OAuthDependency<UUID, UUID>()

for _ in 0 ..< 5000 {
    Task {
        do {
            try await Task.sleep(nanoseconds: UInt64.random(in: 0 ..< maxTime))
            let _: String = try! await oauthRunner.run(
                task: {
                    accessDependency in
                    switch await backend.getResource(clientAccessToken: accessDependency.token) {
                    case .unauthorised:
                        return .dependencyRequiresRefresh
                    case let .ok(string):
                        return .success(string)
                    case .updatedToken:
                        fatalError()
                    }
                },
                refreshAccessToken: {
                    refreshDependency, _ in
                    switch await backend.refresh(clientRefreshToken: refreshDependency.token) {
                    case .unauthorised:
                        return RefreshResult.failedRefresh
                    case .ok:
                        fatalError()
                    case let .updatedToken(uuid):
                        return RefreshResult.refreshedDependency(.init(token: uuid))
                    }
                },
                refreshRefreshToken: {
                    _ in
                    let (backendRefreshToken, backendAccessToken) = await backend.loginWithAccess(password: "PWD")
                    return RefreshResult.refreshedDependency(.init(token: backendRefreshToken.token, accessToken: .init(token: backendAccessToken.token)))
                }
            )

        } catch let error as DependencyError where error.code == .failedRefresh {
            print("Refresh failed")
        } catch let error as DependencyError where error.code == .timeout {
            print("Timeout")
        }
    }
}
try await Task.sleep(nanoseconds: maxTime + 3_000_000_000)
backend.printLog()
```
