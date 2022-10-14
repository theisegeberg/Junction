@testable import Junction
import XCTest

final class JunctionTests: XCTestCase {
    
    struct RDeppie {
        let refresh: UUID
    }
    
    struct Deppie {
        let access: UUID
    }

    
    func testManualOAuth() async throws {
        let backend = FakeOauth()
        let refreshRunner = DependentRunner<RDeppie>()
        let accessRunner = DependentRunner<Deppie>()
        let counter = Counter()

        let maxTime: UInt64 = 10_000_000_000

        for _ in 0 ..< 200 {
            Task {
                try! await Task.sleep(nanoseconds: UInt64.random(in: 0 ..< maxTime))
                let result: RunResult<RunResult<String>> = await refreshRunner.run { refreshDependency in
                    let innerResult: RunResult<String> = await accessRunner.run { accessDependency in
                        let res = await backend.getResource(clientAccessToken: accessDependency.access)
                        switch res {
                        case .unauthorised:
                            return .dependencyRequiresRefresh
                        case let .ok(string):
                            return .success(string)
                        case .updatedToken:
                            fatalError()
                        }
                    } refreshDependency: {
                        let res = await backend.refresh(clientRefreshToken: refreshDependency.refresh)
                        switch res {
                        case .unauthorised:
                            return RefreshResult.failedRefresh
                        case .ok:
                            fatalError()
                        case let .updatedToken(uuid):
                            return RefreshResult.refreshedDependency(Deppie(access: uuid))
                        }
                    }
                    if case .failedRefresh = innerResult {
                        return .dependencyRequiresRefresh
                    }
                    return .success(innerResult)
                } refreshDependency: {
                    let rDeppie = await backend.login(password: "PWD")
                    try await accessRunner.reset()
                    return RefreshResult.refreshedDependency(.init(refresh: rDeppie.token))
                }
                switch result {
                case .success:
                    await counter.increment()
                case .failedRefresh:
                    fatalError("Update failed")
                case let .otherError(error):
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

        let maxTime: UInt64 = 10_000_000_000

        struct Token {
            let value: UUID
        }

        let oauthRunner = TwoStepRunner<Token, Token>(threadSleep: 50_000_000, timeout: 10)

        for _ in 0 ..< 200 {
            Task {
                try! await Task.sleep(nanoseconds: UInt64.random(in: 0 ..< maxTime))
                let result: RunResult<String> = await oauthRunner.run { accessDependency in
                    switch await backend.getResource(clientAccessToken: accessDependency.value) {
                    case .unauthorised:
                        return .dependencyRequiresRefresh
                    case let .ok(string):
                        return .success(string)
                    case .updatedToken:
                        fatalError()
                    }
                } refreshInner: { refreshDependency in
                    switch await backend.refresh(clientRefreshToken: refreshDependency.value) {
                    case .unauthorised:
                        return RefreshResult.failedRefresh
                    case .ok:
                        fatalError()
                    case let .updatedToken(uuid):
                        return RefreshResult.refreshedDependency(.init(value: uuid))
                    }
                } refreshOuter: { innerRunner in
                    let refreshToken = await backend.login(password: "PWD")
                    do {
                        try await innerRunner.reset()
                    } catch {
                        return .failedRefresh
                    }
                    return RefreshResult.refreshedDependency(.init(value: refreshToken.token))
                }
                switch result {
                case .success:
                    await counter.increment()
                case .failedRefresh:
                    fatalError("Update failed")
                case let .otherError(error):
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

        let maxTime: UInt64 = 10_000_000_000

        let oauthRunner = OAuthRunner<UUID, UUID>(threadSleep: 50_000_000, timeout: 10)

        for _ in 0 ..< 200 {
            Task {
                try! await Task.sleep(nanoseconds: UInt64.random(in: 0 ..< maxTime))
                let result: RunResult<String> = await oauthRunner.run({
                    accessDependency in
                    switch await backend.getResource(clientAccessToken: accessDependency.token) {
                    case .unauthorised:
                        return .dependencyRequiresRefresh
                    case let .ok(string):
                        return .success(string)
                    case .updatedToken:
                        fatalError()
                    }
                }, refreshAccessToken: {
                    refreshDependency in
                    switch await backend.refresh(clientRefreshToken: refreshDependency.token) {
                    case .unauthorised:
                        return RefreshResult.failedRefresh
                    case .ok:
                        fatalError()
                    case let .updatedToken(uuid):
                        return RefreshResult.refreshedDependency(.init(token: uuid))
                    }
                }, refreshRefreshToken: {
                    let backendRefreshToken = await backend.login(password: "PWD")
                    return RefreshResult.refreshedDependency(.init(token: backendRefreshToken.token, accessToken: nil))
                })
                switch result {
                case .success:
                    await counter.increment()
                case .failedRefresh:
                    fatalError("Update failed")
                case let .otherError(error):
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
        let timeOutCounter = Counter()

        let maxTime: UInt64 = 10_000_000_000

        let oauthRunner = OAuthRunner<UUID, UUID>(threadSleep: 50_000_000, timeout: 2.2)

        for _ in 0 ..< 500 {
            Task {
                try! await Task.sleep(nanoseconds: UInt64.random(in: 0 ..< maxTime))
                let result: RunResult<String> = await oauthRunner.run({
                    accessDependency in
                    switch await backend.getResource(clientAccessToken: accessDependency.token) {
                    case .unauthorised:
                        return .dependencyRequiresRefresh
                    case let .ok(string):
                        return .success(string)
                    case .updatedToken:
                        fatalError()
                    }
                }, refreshAccessToken: {
                    refreshDependency in
                    switch await backend.refresh(clientRefreshToken: refreshDependency.token) {
                    case .unauthorised:
                        return RefreshResult.failedRefresh
                    case .ok:
                        fatalError()
                    case let .updatedToken(uuid):
                        return RefreshResult.refreshedDependency(.init(token: uuid))
                    }
                }, refreshRefreshToken: {
                    let (backendRefreshToken, backendAccessToken) = await backend.loginWithAccess(password: "PWD")
                    return RefreshResult.refreshedDependency(.init(token: backendRefreshToken.token, accessToken: .init(token: backendAccessToken.token)))
                })
                switch result {
                case .success:
                    await counter.increment()
                case .failedRefresh:
                    fatalError("Update failed")
                case let .otherError(error):
                    fatalError(error.localizedDescription)
                case .timeout:
                    await timeOutCounter.increment()
                }
            }
        }
        try await Task.sleep(nanoseconds: maxTime + 3_000_000_000)
        backend.printLog()
        print(await counter.getCount())
        print(await timeOutCounter.getCount())
    }
}
