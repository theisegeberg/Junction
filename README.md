# Junction
A graceful layered try - refresh - retry library for OAuth and the likes.

---

This small library solves the problem posed OAuth style flows where multiple layers of retrying needs to happen in concert.

In OAuth there is some sort of login that will produce an authorization code. The authorization code can be exchanged for a refresh token. And this refresh token can be used to make short lived access tokens. An access token can be used to access resources from a server.

The solution provided here gives the following benefits:
1. *Full chain retry and resume for OAuth:* If a call fails, then it can refresh the access token with the refresh token, and then retry the call. If the refresh call fails, it can update the refresh token with a new login from the user, and retry all the way down.
2. *Full concurrency support:* If multiple calls all fail at their updates simultaneously, only one refresh will be attempted. This also goes for layered dependencies.
3. *Multi-layer retry support:* Multiple dependencies can be nested, with support for the child dependencies being reset when a parent dependency is updated. 
4. *Capture safe:* No closures are ever stored, so it's safe to use `self` and anything else here.
5. *Unassuming:* No strict reference to any transport layer concepts like HTTPS. And no references to encoding schemes like JSON. Also does provides both closure based and protocol based call site.
6. *Location agnostic:* Can be placed at either the top: Where the call is being performed closer to the outer edge of the code. Or hidden away at the inner core of the logic that needs to be rerouted. Doesn't provide any framework, just a few concepts that wraps other code.
7. *Flexible:* Can start from a point of any existing dependencies. Even a complex scenario like having an outer, middle and inner dependency, where only the middle is known in advance, can be resumed.
8. *Portable*: Tiny code base that can easily be moved into your project without any problems.
9. *Supportive:* Supports Catalina iOS 13.

---

The test target has a fake OAuth server to test the functionality.

## Example usage

```Swift
let backend = FakeOauth()

let maxTime: UInt64 = 10_000_000_000

let oauthRunner = OAuthDependency<UUID, UUID>(threadSleep: 50_000_000, timeout: 2.2)

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
