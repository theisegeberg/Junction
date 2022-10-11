
import Foundation


protocol RefreshTokenProviding {
    var refreshToken:UUID { get }
}

protocol AccessTokenCarrier {
    var accessToken:AccessTokenProviding { get }
}

protocol AccessTokenProviding {
    var accessToken:UUID { get }
}

struct OAuthRunner {
    
    let outerRunner:DependentRunner<RefreshTokenProviding>
    let innerRunner:DependentRunner<AccessTokenProviding>
    
    public init(threadSleep:UInt64, timeout:TimeInterval) {
        self.outerRunner = .init(threadSleep: threadSleep, defaultTimeout: timeout)
        self.innerRunner = .init(threadSleep: threadSleep, defaultTimeout: timeout)
    }
    
    public func run<Success>(
        _ runBlock: (AccessTokenProviding) async -> TaskResult<Success>,
        updateInner: (RefreshTokenProviding) async -> RefreshResult<AccessTokenProviding>,
        updateOuter: () async -> RefreshResult<RefreshTokenProviding>
    ) async -> RunResult<Success> {
        await outerRunner.run {
            refreshDependency in
            let innerResult = await innerRunner.run {
                accessDependency in
                await runBlock(accessDependency)
            } updateDependency: {
                await updateInner(refreshDependency)
            }
            if case .failedRefresh = innerResult {
                return .dependencyRequiresRefresh
            }
            return .success(innerResult)
        } updateDependency: {
            switch await updateOuter() {
                case .failedRefresh:
                    return .failedRefresh
                case .refreshedDependency(let updatedRefreshToken):
                    await innerRunner.reset()
                    if let accessTokenProviding = updatedRefreshToken as? AccessTokenCarrier {
                        await innerRunner.refresh(dependency: accessTokenProviding.accessToken)
                    }
                    return .refreshedDependency(updatedRefreshToken)
            }
        }
        .flatMap { $0 }
    }
}
