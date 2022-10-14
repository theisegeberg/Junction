
import Foundation

public struct OAuthRunner<RefreshTokenType, AccessTokenType> {
    public struct RefreshToken {
        let token: RefreshTokenType
        let accessToken: AccessToken?
    }

    public struct AccessToken {
        let token: AccessTokenType
    }

    private let twoStepRunner: TwoStepRunner<RefreshToken, AccessToken>

    public init(threadSleep: UInt64, timeout: TimeInterval) {
        twoStepRunner = .init(threadSleep: threadSleep, timeout: timeout)
    }

    public func run<Success>(
        _ context: any OAuthRunnerContext<Success, RefreshToken, AccessToken>
    ) async -> RunResult<Success> {
        await run(context.run, refreshAccessToken: context.refreshAccessToken, refreshRefreshToken: context.refreshRefreshToken)
    }

    public func run<Success>(
        _ runBlock: (AccessToken) async throws -> TaskResult<Success>,
        refreshAccessToken: (RefreshToken) async throws -> RefreshResult<AccessToken>,
        refreshRefreshToken: () async throws -> RefreshResult<RefreshToken>
    ) async -> RunResult<Success> {
        await twoStepRunner.run({
            accessDependency in
            try await runBlock(accessDependency)
        }, refreshInner: { refreshDependency in
            try await refreshAccessToken(refreshDependency)
        }, refreshOuter: { accessRunner in
            switch try await refreshRefreshToken() {
            case .failedRefresh:
                return .failedRefresh
            case let .refreshedDependency(refreshToken):
                if let accessToken = refreshToken.accessToken {
                    try await accessRunner.refresh(dependency: accessToken)
                } else {
                    try await accessRunner.reset()
                }
                return .refreshedDependency(refreshToken)
            }
        })
    }
}
