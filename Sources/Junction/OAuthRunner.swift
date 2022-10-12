
import Foundation

public protocol RefreshTokenProviding {
    var refreshToken: UUID { get }
}

public protocol AccessTokenCarrier {
    var accessToken: AccessTokenProviding { get }
}

public protocol AccessTokenProviding {
    var accessToken: UUID { get }
}

public protocol OAuthRunnerContext<Success> {
    associatedtype Success
    func run(_ accessToken:AccessTokenProviding) async -> TaskResult<Success>
    func updateAccessToken(_ refreshToken:RefreshTokenProviding) async -> RefreshResult<AccessTokenProviding>
    func updateRefreshToken() async -> RefreshResult<RefreshTokenProviding>
}

public struct OAuthRunner {
    let outerRunner: DependentRunner<RefreshTokenProviding>
    let innerRunner: DependentRunner<AccessTokenProviding>

    public init(threadSleep: UInt64, timeout: TimeInterval) {
        outerRunner = .init(threadSleep: threadSleep, defaultTimeout: timeout)
        innerRunner = .init(threadSleep: threadSleep, defaultTimeout: timeout)
    }

    public func run<Success>(
        _ context: any OAuthRunnerContext<Success>
    ) async -> RunResult<Success> {
        await run(context.run, updateAccessToken: context.updateAccessToken, updateRefreshToken: context.updateRefreshToken)
    }
    
    public func run<Success>(
        _ runBlock: (AccessTokenProviding) async -> TaskResult<Success>,
        updateAccessToken: (RefreshTokenProviding) async -> RefreshResult<AccessTokenProviding>,
        updateRefreshToken: () async -> RefreshResult<RefreshTokenProviding>
    ) async -> RunResult<Success> {
        await outerRunner.run {
            refreshDependency in
            let innerResult = await innerRunner.run {
                accessDependency in
                await runBlock(accessDependency)
            } updateDependency: {
                await updateAccessToken(refreshDependency)
            }
            if case .failedRefresh = innerResult {
                return .dependencyRequiresRefresh
            }
            return .success(innerResult)
        } updateDependency: {
            switch await updateRefreshToken() {
            case .failedRefresh:
                return .failedRefresh
            case let .refreshedDependency(updatedRefreshToken):
                if let accessTokenProviding = updatedRefreshToken as? AccessTokenCarrier {
                    await innerRunner.refresh(dependency: accessTokenProviding.accessToken)
                } else {
                    await innerRunner.reset()
                }
                return .refreshedDependency(updatedRefreshToken)
            }
        }
        .flatMap { $0 }
    }
}
