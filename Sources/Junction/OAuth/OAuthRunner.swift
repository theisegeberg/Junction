
import Foundation

public struct OAuthRunner<RefreshTokenType, AccessTokenType> {
    public struct RefreshToken {
        let token: RefreshTokenType
        let accessToken: AccessToken?
    }

    public struct AccessToken {
        let token: AccessTokenType
    }

    let refreshRunner: DependentRunner<RefreshToken>
    let accessRunner: DependentRunner<AccessToken>

    public init(threadSleep: UInt64, timeout: TimeInterval) {
        refreshRunner = .init(threadSleep: threadSleep, defaultTimeout: timeout)
        accessRunner = .init(threadSleep: threadSleep, defaultTimeout: timeout)
    }

    public func run<Success>(
        _ context: any OAuthRunnerContext<Success, RefreshToken, AccessToken>
    ) async -> RunResult<Success> {
        await run(context.run, refreshAccessToken: context.refreshAccessToken, refreshRefreshToken: context.refreshRefreshToken)
    }

    public func run<Success>(
        _ runBlock: (AccessToken) async -> TaskResult<Success>,
        refreshAccessToken: (RefreshToken) async -> RefreshResult<AccessToken>,
        refreshRefreshToken: () async -> RefreshResult<RefreshToken>
    ) async -> RunResult<Success> {
        await refreshRunner.run {
            refreshDependency in

            let innerResult = await accessRunner.run {
                accessDependency in
                await runBlock(accessDependency)
            } refreshDependency: {
                await refreshAccessToken(refreshDependency)
            }
            if case .failedRefresh = innerResult {
                return .dependencyRequiresRefresh
            }
            return .success(innerResult)

        } refreshDependency: {
            switch await refreshRefreshToken() {
            case .failedRefresh:
                return .failedRefresh
            case let .refreshedDependency(refreshToken):
                if let accessToken = refreshToken.accessToken {
                    await accessRunner.refresh(dependency: accessToken)
                } else {
                    await accessRunner.reset()
                }
                return .refreshedDependency(refreshToken)
            }
        }
        .flatMap { $0 }
    }
}
