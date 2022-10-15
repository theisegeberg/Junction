
import Foundation

/// A specialised `TwoStepRunner` that handles OAuth like scenarios.
public struct OAuthDependency<RefreshTokenType, AccessTokenType> {
    public struct RefreshToken {
        let token: RefreshTokenType
        let accessToken: AccessToken?
    }

    public struct AccessToken {
        let token: AccessTokenType
    }

    private let twoStepRunner: LayeredDependency<RefreshToken, AccessToken>

    public init(refreshToken: RefreshToken? = nil, accessToken: AccessToken? = nil, threadSleep: UInt64, timeout: TimeInterval) {
        twoStepRunner = .init(outerDependency: refreshToken, innerDependency: accessToken, threadSleep: threadSleep, defaultTimeout: timeout)
    }

    public func run<Success>(
        _ proxy: any OAuthDependencyProxy<Success, RefreshToken, AccessToken>
    ) async throws -> RunResult<Success> {
        try await run(proxy.run, refreshAccessToken: proxy.refreshAccessToken, refreshRefreshToken: proxy.refreshRefreshToken)
    }

    public func run<Success>(
        _ runBlock: (AccessToken) async throws -> TaskResult<Success>,
        refreshAccessToken: (RefreshToken) async throws -> RefreshResult<AccessToken>,
        refreshRefreshToken: () async throws -> RefreshResult<RefreshToken>
    ) async throws -> RunResult<Success> {
        try await twoStepRunner.run({
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
