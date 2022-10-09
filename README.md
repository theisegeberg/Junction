# Junction

This library solves the problem posed OAuth style flows where multiple layers of retrying needs to happen in concert.

In OAuth there is some sort of login that will produce an authorization code. The authorization code can be exchanged for a refresh token. And this refresh token can be used to make short lived access tokens. An access token can be used to access resources from a server.

The solution provided here gives the following benefits:
1. Full chain retry and resume: If a call fails, then it can refresh the access token with the refresh token, and then retry the call. If the refresh call fails, it can update the refresh token with a new login from the user, and retry all the way down.
2. Full concurrent support: If multiple calls all fail at their updates simultaneously, only one refresh will be attempted.
3. Multi-layer retry support: Multiple dependencies can be nested, with support for the child dependencies being reset when a parent dependency is updated. 

The test target has a fake OAuth server to test the functionality.

```Swift
let backend = FakeOauth()
let counter = Counter()

let maxTime:UInt64 = 10_000_000_000

let oauthRunner = OAuthDependentRunner()

for _ in 0..<200 {
    Task {
        try! await Task.sleep(nanoseconds: UInt64.random(in: 0..<maxTime))
        let result:RunResult<String> = await oauthRunner.run { accessDependency in
            switch await backend.getResource(clientAccessToken: accessDependency.value) {
                case .unauthorised:
                    return .badDependency
                case .ok(let string):
                    return .output(string)
                case .updatedToken:
                    fatalError()
            }
        } updateAccessToken: { refreshDependency in
            switch await backend.refresh(clientRefreshToken: refreshDependency.value) {
                case .unauthorised:
                    return UpdateResult.updateFailed
                case .ok:
                    fatalError()
                case .updatedToken(let uuid):
                    return UpdateResult.updatedDependency(.init(value: uuid))
            }
        } updateRefreshToken: {
            let refreshToken = await backend.login(password: "PWD")
            return UpdateResult.updatedDependency(.init(value: refreshToken.token))
        }
        switch result {
            case .output:
                await counter.increment()
            case .updateFailed:
                fatalError()
            case .otherError(let error):
                fatalError(error.localizedDescription)
        }
    }
}
try await Task.sleep(nanoseconds: maxTime + 5_000_000_000)
```
