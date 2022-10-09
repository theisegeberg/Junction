//
//  OAuthDependentRunner.swift
//  DepInversionTest
//
//  Created by Theis Egeberg on 09/10/2022.
//

import Foundation

class OAuthDependentRunner {
    
    struct RefreshToken {
        let value:UUID
    }
    
    struct AccessToken {
        let value:UUID
    }
    
    let refreshRunner:DependentRunner<RefreshToken>
    let accessRunner:DependentRunner<AccessToken>
    
    init(
        refreshRunner: DependentRunner<RefreshToken> = .init(),
        accessRunner: DependentRunner<AccessToken> = .init()
    ) {
        self.refreshRunner = refreshRunner
        self.accessRunner = accessRunner
    }
    
    func run<Output>(
        task: (AccessToken) async -> TaskResult<Output>,
        updateAccessToken: (RefreshToken) async -> UpdateResult<AccessToken>,
        updateRefreshToken: () async -> UpdateResult<RefreshToken>
    ) async -> RunResult<Output> {
        let result:RunResult<RunResult<Output>> = await refreshRunner.run(childRunner: accessRunner) { refreshDependency in
            let innerResult:RunResult<Output> = await accessRunner.run { accessDependency in
                return await task(accessDependency)
            } updateDependency: {
                return await updateAccessToken(refreshDependency)
            }
            if case .updateFailed = innerResult {
                return .badDependency
            }
            return .output(innerResult)
        } updateDependency: {
            await updateRefreshToken()
        }
        return result.flatMap { $0 }

    }
    
    
}
