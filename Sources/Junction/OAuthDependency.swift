
import Foundation

/// A manager for two `Dependency` objects that handles OAuth like scenarios.
public struct OAuthDependency<RefreshTokenType, AccessTokenType> {
    public struct RefreshToken {
        let token: RefreshTokenType
        let accessToken: AccessToken?
    }

    public struct AccessToken {
        let token: AccessTokenType
    }

    private let refreshDependency: Dependency<RefreshToken>
    private let accessDependency: Dependency<AccessToken>

    
    public init(threadSleep: UInt64, timeout: TimeInterval) {
        refreshDependency = .init(threadSleep: threadSleep, defaultTimeout: timeout)
        accessDependency = .init(threadSleep: threadSleep, defaultTimeout: timeout)
    }

    public func run<Success>(
        task: (AccessToken) async throws -> TaskResult<Success>,
        refreshAccessToken: (RefreshToken, AccessToken?) async throws -> RefreshResult<AccessToken>,
        refreshRefreshToken: (RefreshToken?) async throws -> RefreshResult<RefreshToken>,
        timeout: TimeInterval? = nil
    ) async throws -> Success {
        try await refreshDependency
            .mapRun(dependency: accessDependency, task: {
                _, accessDependency in
                try await task(accessDependency)
            }, innerRefresh: {
                refreshDependency, failedAccessToken in
                try await refreshAccessToken(refreshDependency, failedAccessToken)
            }, outerRefresh: {
                accessRunner, failedRefreshToken in
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
