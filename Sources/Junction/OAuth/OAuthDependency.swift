
import Foundation

/// A specialised `LayeredDependency` that handles OAuth like scenarios.
public struct OAuthDependency<RefreshTokenType, AccessTokenType> {
    public struct RefreshToken {
        let token: RefreshTokenType
        let accessToken: AccessToken?
    }

    public struct AccessToken {
        let token: AccessTokenType
    }

    private let dependency: LayeredDependency<RefreshToken, AccessToken>

    public init(refreshToken: RefreshToken? = nil, accessToken: AccessToken? = nil, threadSleep: UInt64, timeout: TimeInterval) {
        dependency = .init(outerDependency: refreshToken, innerDependency: accessToken, threadSleep: threadSleep, defaultTimeout: timeout)
    }

    public func run<Success>(
        _ proxy: any OAuthDependencyProxy<Success, RefreshToken, AccessToken>
    ) async throws -> Success {
        try await run(proxy.run, refreshAccessToken: proxy.refreshAccessToken, refreshRefreshToken: proxy.refreshRefreshToken)
    }

    public func run<Success>(
        _ runBlock: (AccessToken) async throws -> TaskResult<Success>,
        refreshAccessToken: (RefreshToken, AccessToken?) async throws -> RefreshResult<AccessToken>,
        refreshRefreshToken: (RefreshToken?) async throws -> RefreshResult<RefreshToken>
    ) async throws -> Success {
        try await dependency.run({
            accessDependency in
            try await runBlock(accessDependency)
        }, refreshInner: { refreshDependency, failedAccessToken in
            try await refreshAccessToken(refreshDependency, failedAccessToken)
        }, refreshOuter: { accessRunner, failedRefreshToken in
            switch try await refreshRefreshToken(failedRefreshToken) {
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
