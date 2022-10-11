import XCTest
@testable import Junction

final class JunctionTests: XCTestCase {
    
    struct RDeppie {
        let refresh:UUID
    }
    
    struct Deppie {
        let access:UUID
    }
    
    func testManualOAuth() async throws {
        let backend = FakeOauth()
        let refreshRunner = DependentRunner<RDeppie>()
        let accessRunner = DependentRunner<Deppie>()
        let counter = Counter()
        
        let maxTime:UInt64 = 10_000_000_000
        
        for _ in 0..<200 {
            Task {
                try! await Task.sleep(nanoseconds: UInt64.random(in: 0..<maxTime))
                let result:RunResult<RunResult<String>> = await refreshRunner.run { refreshDependency in
                    let innerResult:RunResult<String> = await accessRunner.run { accessDependency in
                        let res = await backend.getResource(clientAccessToken: accessDependency.access)
                        switch res {
                            case .unauthorised:
                                return .dependencyRequiresRefresh
                            case .ok(let string):
                                return .success(string)
                            case .updatedToken:
                                fatalError()
                        }
                    } updateDependency: {
                        let res = await backend.refresh(clientRefreshToken: refreshDependency.refresh)
                        switch res {
                            case .unauthorised:
                                return RefreshResult.failedRefresh
                            case .ok:
                                fatalError()
                            case .updatedToken(let uuid):
                                return RefreshResult.refreshedDependency(Deppie(access: uuid))
                        }
                    }
                    if case .failedRefresh = innerResult {
                        return .dependencyRequiresRefresh
                    }
                    return .success(innerResult)
                } updateDependency: {
                    let rDeppie = await backend.login(password: "PWD")
                    await accessRunner.reset()
                    return RefreshResult.refreshedDependency(.init(refresh: rDeppie.token))
                }
                switch result {
                    case .success:
                        await counter.increment()
                    case .failedRefresh:
                        fatalError("Update failed")
                    case .otherError(let error):
                        fatalError(error.localizedDescription)
                    case .timeout:
                        fatalError("Timed out")
                }
            }
        }
        try await Task.sleep(nanoseconds: maxTime + 5_000_000_000)
        print(await counter.getCount())
        
    }
    
    
    
    func testDedicatedOAuth() async throws {
        let backend = FakeOauth()
        let counter = Counter()
        
        let maxTime:UInt64 = 10_000_000_000
        
        struct Token {
            let value:UUID
        }
        
        let oauthRunner = TwoStepRunner<Token,Token>()
        
        for _ in 0..<200 {
            Task {
                try! await Task.sleep(nanoseconds: UInt64.random(in: 0..<maxTime))
                let result:RunResult<String> = await oauthRunner.run { accessDependency in
                    switch await backend.getResource(clientAccessToken: accessDependency.value) {
                        case .unauthorised:
                            return .dependencyRequiresRefresh
                        case .ok(let string):
                            return .success(string)
                        case .updatedToken:
                            fatalError()
                    }
                } updateInner: { refreshDependency in
                    switch await backend.refresh(clientRefreshToken: refreshDependency.value) {
                        case .unauthorised:
                            return RefreshResult.failedRefresh
                        case .ok:
                            fatalError()
                        case .updatedToken(let uuid):
                            return RefreshResult.refreshedDependency(.init(value: uuid))
                    }
                } updateOuter: {
                    let refreshToken = await backend.login(password: "PWD")
                    return RefreshResult.refreshedDependency(.init(value: refreshToken.token))
                }
                switch result {
                    case .success:
                        await counter.increment()
                    case .failedRefresh:
                        fatalError("Update failed")
                    case .otherError(let error):
                        fatalError(error.localizedDescription)
                    case .timeout:
                        fatalError("Timed out")
                }
            }
        }
        try await Task.sleep(nanoseconds: maxTime + 5_000_000_000)
        print(await counter.getCount())
        
    }
    
    
    
    func testDedicatedOAuth2() async throws {
        let backend = FakeOauth()
        let counter = Counter()
        
        let maxTime:UInt64 = 10_000_000_000
        
        struct Token {
            let value:UUID
        }
        
        let oauthRunner = OAuthRunner(threadSleep: 50_000_000, timeout: 10)
        
        for _ in 0..<200 {
            Task {
                try! await Task.sleep(nanoseconds: UInt64.random(in: 0..<maxTime))
                let result:RunResult<String> = await oauthRunner.run({
                    accessDependency in
                    switch await backend.getResource(clientAccessToken: accessDependency.accessToken) {
                        case .unauthorised:
                            return .dependencyRequiresRefresh
                        case .ok(let string):
                            return .success(string)
                        case .updatedToken:
                            fatalError()
                    }
                }, updateInner: {
                    refreshDependency in
                    switch await backend.refresh(clientRefreshToken: refreshDependency.refreshToken) {
                        case .unauthorised:
                            return RefreshResult.failedRefresh
                        case .ok:
                            fatalError()
                        case .updatedToken(let uuid):
                            struct AccessToken:AccessTokenProviding {
                                var accessToken: UUID
                            }
                            return RefreshResult.refreshedDependency(AccessToken(accessToken: uuid))
                    }
                }, updateOuter: {
                    let backendRefreshToken = await backend.login(password: "PWD")
                    struct RefreshToken:RefreshTokenProviding {
                        var refreshToken: UUID
                    }
                    return RefreshResult.refreshedDependency(RefreshToken(refreshToken: backendRefreshToken.token))
                })
                switch result {
                    case .success:
                        await counter.increment()
                    case .failedRefresh:
                        fatalError("Update failed")
                    case .otherError(let error):
                        fatalError(error.localizedDescription)
                    case .timeout:
                        fatalError("Timed out")
                }
            }
        }
        try await Task.sleep(nanoseconds: maxTime + 5_000_000_000)
        print(await counter.getCount())
        
    }
    
    
    
    func testDedicatedOAuthWithAccessAndRefresh() async throws {
        let backend = FakeOauth()
        let counter = Counter()
        
        let maxTime:UInt64 = 10_000_000_000
        
        struct Token {
            let value:UUID
        }
        
        let oauthRunner = OAuthRunner(threadSleep: 50_000_000, timeout: 10)
        
        for _ in 0..<200 {
            Task {
                try! await Task.sleep(nanoseconds: UInt64.random(in: 0..<maxTime))
                let result:RunResult<String> = await oauthRunner.run({
                    accessDependency in
                    switch await backend.getResource(clientAccessToken: accessDependency.accessToken) {
                        case .unauthorised:
                            return .dependencyRequiresRefresh
                        case .ok(let string):
                            return .success(string)
                        case .updatedToken:
                            fatalError()
                    }
                }, updateInner: {
                    refreshDependency in
                    switch await backend.refresh(clientRefreshToken: refreshDependency.refreshToken) {
                        case .unauthorised:
                            return RefreshResult.failedRefresh
                        case .ok:
                            fatalError()
                        case .updatedToken(let uuid):
                            struct AccessToken:AccessTokenProviding {
                                var accessToken: UUID
                            }
                            return RefreshResult.refreshedDependency(AccessToken(accessToken: uuid))
                    }
                }, updateOuter: {
                    let (backendRefreshToken, backendAccessToken) = await backend.loginWithAccess(password: "PWD")
                    struct RefreshToken:RefreshTokenProviding, AccessTokenCarrier {
                        var refreshToken: UUID
                        var accessToken: AccessTokenProviding
                    }
                    struct AccessToken:AccessTokenProviding {
                        var accessToken: UUID
                    }
                    return RefreshResult.refreshedDependency(RefreshToken(refreshToken: backendRefreshToken.token, accessToken: AccessToken(accessToken: backendAccessToken.token)))
                })
                switch result {
                    case .success:
                        await counter.increment()
                    case .failedRefresh:
                        fatalError("Update failed")
                    case .otherError(let error):
                        fatalError(error.localizedDescription)
                    case .timeout:
                        fatalError("Timed out")
                }
            }
        }
        try await Task.sleep(nanoseconds: maxTime + 5_000_000_000)
        print(await counter.getCount())
        
    }
    
}
