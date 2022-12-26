import XCTest
@testable import Junction

final class JunctionTests: XCTestCase {
    func testDedicatedOAuthWithPureRefresh() async throws {
        let backend = FakeOauth()
        let counter = Counter()
        
        let maxTime: UInt64 = 5_000_000_000
        
        let oauthRunner = OAuthDependency<UUID, UUID>(refreshConfiguration: .default, accessConfiguration: .default)
        
        let taskCount = 200
        
        let refreshExpectation = XCTestExpectation(description: "Refresh token was refreshed")
        let accessExpectation = XCTestExpectation(description: "Access token was refreshed")
        let completeExpectation = XCTestExpectation(description: "200 runs achieved")
        
        for _ in 0 ..< taskCount {
            Task {
                do {
                    try await Task.sleep(nanoseconds: UInt64.random(in: 0 ..< maxTime))
                    let result: String = try await oauthRunner.run(
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
                                    accessExpectation.fulfill()
                                    return RefreshResult.refreshedDependency(.init(token: uuid))
                            }
                        },
                        refreshRefreshToken: { _ in
                            let backendRefreshToken = await backend.login(password: "PWD")
                            refreshExpectation.fulfill()
                            return RefreshResult.refreshedDependency(.init(token: backendRefreshToken.token, accessToken: nil))
                        }
                    )
                    XCTAssert(result == "<html><body>Hello world!</body></html>")
                    if result == "<html><body>Hello world!</body></html>" {
                        await counter.increment()
                    }
                    if await counter.getCount() == taskCount {
                        completeExpectation.fulfill()
                    }
                } catch let error as DependencyError where error.code == .failedRefresh {
                    fatalError("Refresh failed")
                }
            }
        }
        //try await Task.sleep(nanoseconds: maxTime + 2_000_000_000)
        wait(for: [accessExpectation, refreshExpectation, completeExpectation], timeout: 10)
        let finalCount = await counter.getCount()
        XCTAssert(finalCount == taskCount)
    }
    
    func testDedicatedOAuthWithAccessAndRefresh() async throws {
        let backend = FakeOauth()
        let counter = Counter()
        let timeOutCounter = Counter()
        
        let maxTime: UInt64 = 10_000_000_000
        
        let oauthRunner = OAuthDependency<UUID, UUID>(refreshConfiguration: .default, accessConfiguration: .default)
        
        for _ in 0 ..< 500 {
            Task {
                do {
                    try await Task.sleep(nanoseconds: UInt64.random(in: 0 ..< maxTime))
                    let _: String = try await oauthRunner.run(
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
                                    return .failedRefresh
                                case .ok:
                                    fatalError()
                                case let .updatedToken(uuid):
                                    return .refreshedDependency(.init(token: uuid))
                            }
                        },
                        refreshRefreshToken: {
                            _ in
                            let (backendRefreshToken, backendAccessToken) = await backend.loginWithAccess(password: "PWD")
                            return RefreshResult.refreshedDependency(.init(token: backendRefreshToken.token, accessToken: .init(token: backendAccessToken.token)))
                        }
                    )
                    await counter.increment()
                    
                } catch let error as DependencyError where error.code == .failedRefresh {
                    fatalError("Refresh failed")
                }
            }
        }
        try await Task.sleep(nanoseconds: maxTime + 3_000_000_000)
        backend.printLog()
        print(await counter.getCount())
        print(await timeOutCounter.getCount())
    }
    
}
