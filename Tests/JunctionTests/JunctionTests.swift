@testable import Junction
import XCTest

final class JunctionTests: XCTestCase {
    func testDedicatedOAuthWithPureRefresh() async throws {
        let backend = FakeOauth()
        let counter = Counter()

        let maxTime: UInt64 = 10_000_000_000

        let oauthRunner = OAuthDependency<UUID, UUID>(threadSleep: 50_000_000, timeout: 10)

        for _ in 0 ..< 200 {
            Task {
                do {
                    try await Task.sleep(nanoseconds: UInt64.random(in: 0 ..< maxTime))
                    let _: String = try! await oauthRunner.run({
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
                        refreshDependency, _ in
                        switch await backend.refresh(clientRefreshToken: refreshDependency.token) {
                        case .unauthorised:
                            return RefreshResult.failedRefresh
                        case .ok:
                            fatalError()
                        case let .updatedToken(uuid):
                            return RefreshResult.refreshedDependency(.init(token: uuid))
                        }
                    }, refreshRefreshToken: { _ in
                        let backendRefreshToken = await backend.login(password: "PWD")
                        return RefreshResult.refreshedDependency(.init(token: backendRefreshToken.token, accessToken: nil))
                    })
                    await counter.increment()
                } catch let error as DependencyError where error.code == .failedRefresh {
                    fatalError("Refresh failed")
                } catch let error as DependencyError where error.code == .timeout {
                    fatalError("Timeout")
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

        let oauthRunner = OAuthDependency<UUID, UUID>(threadSleep: 50_000_000, timeout: 2.2)

        for _ in 0 ..< 500 {
            Task {
                do {
                    try await Task.sleep(nanoseconds: UInt64.random(in: 0 ..< maxTime))
                    let _: String = try! await oauthRunner.run({
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
                        refreshDependency, _ in
                        switch await backend.refresh(clientRefreshToken: refreshDependency.token) {
                        case .unauthorised:
                            return RefreshResult.failedRefresh
                        case .ok:
                            fatalError()
                        case let .updatedToken(uuid):
                            return RefreshResult.refreshedDependency(.init(token: uuid))
                        }
                    }, refreshRefreshToken: {
                        _ in
                        let (backendRefreshToken, backendAccessToken) = await backend.loginWithAccess(password: "PWD")
                        return RefreshResult.refreshedDependency(.init(token: backendRefreshToken.token, accessToken: .init(token: backendAccessToken.token)))
                    })
                    await counter.increment()

                } catch let error as DependencyError where error.code == .failedRefresh {
                    fatalError("Refresh failed")
                } catch let error as DependencyError where error.code == .timeout {
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
