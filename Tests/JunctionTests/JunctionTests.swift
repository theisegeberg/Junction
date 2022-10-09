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
                let result:RunResult<RunResult<String>> = await refreshRunner.run(childRunner: accessRunner) { refreshDependency in
                    let innerResult:RunResult<String> = await accessRunner.run { accessDependency in
                        let res = await backend.getResource(clientAccessToken: accessDependency.access)
                        switch res {
                            case .unauthorised:
                                return .badDependency
                            case .ok(let string):
                                return .output(string)
                            case .updatedToken:
                                fatalError()
                        }
                    } updateDependency: {
                        let res = await backend.refresh(clientRefreshToken: refreshDependency.refresh)
                        switch res {
                            case .unauthorised:
                                return UpdateResult.updateFailed
                            case .ok:
                                fatalError()
                            case .updatedToken(let uuid):
                                return UpdateResult.updatedDependency(Deppie(access: uuid))
                        }
                    }
                    if case .updateFailed = innerResult {
                        return .badDependency
                    }
                    return .output(innerResult)
                    
                    
                    
                } updateDependency: {
                    let rDeppie = await backend.login(password: "PWD")
                    return UpdateResult.updatedDependency(.init(refresh: rDeppie.token))
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
        print(await counter.getI())
        
    }
    
    
    
    func testDedicatedOAuth() async throws {
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
        print(await counter.getI())
        
    }
    
}
