//
//  OAuthDependentRunner.swift
//  DepInversionTest
//
//  Created by Theis Egeberg on 09/10/2022.
//

import Foundation

class OAuthDependentRunner<RefreshToken,AccessToken> {
    
    let refreshRunner:DependentRunner<RefreshToken>
    let accessRunner:DependentRunner<AccessToken>
    
    init(
        refreshRunner: DependentRunner<RefreshToken> = .init(),
        accessRunner: DependentRunner<AccessToken> = .init()
    ) {
        self.refreshRunner = refreshRunner
        self.accessRunner = accessRunner
    }
    
    func run<Success>(
        task: (AccessToken) async -> TaskResult<Success>,
        updateAccessToken: (RefreshToken) async -> RefreshResult<AccessToken>,
        updateRefreshToken: () async -> RefreshResult<RefreshToken>
    ) async -> RunResult<Success> {
        await refreshRunner.run(childRunner: accessRunner) {
            refreshDependency in
            let innerResult = await accessRunner.run {
                accessDependency in
                await task(accessDependency)
            } updateDependency: {
                await updateAccessToken(refreshDependency)
            }
            if case .failedRefresh = innerResult {
                return .dependencyRequiresRefresh
            }
            return .success(innerResult)
        } updateDependency: {
            await updateRefreshToken()
        }
        .flatMap { $0 }
    }
    
    
}
