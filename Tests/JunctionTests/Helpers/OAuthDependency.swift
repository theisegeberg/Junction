
import Foundation
import Junction

/// A manager for two `Dependency` objects that handles OAuth like scenarios.
///
/// This is purely intended as an example implementation. It does not cover the entirety of the OAuth flow.
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

    public init(refreshConfiguration: DependencyConfiguration, accessConfiguration: DependencyConfiguration) {
        refreshDependency = .init(configuration: refreshConfiguration)
        accessDependency = .init(configuration: accessConfiguration)
    }

    public func run<Success>(
        task: (AccessToken) async throws -> TaskResult<Success>,
        refreshAccessToken: (RefreshToken, AccessToken?) async throws -> AccessToken?,
        refreshRefreshToken: (RefreshToken?) async throws -> RefreshToken?,
        timeout _: TimeInterval? = nil
    ) async throws -> Success {
        try await refreshDependency
            .mapRun(dependency: accessDependency, task: {
                _,accessDependency,_ in
                try await task(accessDependency)
            }, innerRefresh: {
                refreshDependency, failedAccessToken, _ in
                try await refreshAccessToken(refreshDependency, failedAccessToken)
            }, outerRefresh: {
                accessRunner, failedRefreshToken, _ in
                switch try await refreshRefreshToken(failedRefreshToken) {
                case .none:
                    return nil
                case let .some(refreshToken):
                    if let accessToken = refreshToken.accessToken {
                        try await accessRunner.refresh(dependency: accessToken)
                    } else {
                        try await accessRunner.reset()
                    }
                    return refreshToken
                }
            })
    }
}
