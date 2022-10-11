//
//  OAuthDependentRunner.swift
//  DepInversionTest
//
//  Created by Theis Egeberg on 09/10/2022.
//

import Foundation

class TwoStepRunner<OuterDependency,InnerDependency> {
    
    let outerRunner:DependentRunner<OuterDependency>
    let innerRunner:DependentRunner<InnerDependency>
    
    init(
        outerRunner: DependentRunner<OuterDependency> = .init(),
        innerRunner: DependentRunner<InnerDependency> = .init()
    ) {
        self.outerRunner = outerRunner
        self.innerRunner = innerRunner
    }
    
    func run<Success>(
        _ runBlock: (InnerDependency) async -> TaskResult<Success>,
        updateInner: (OuterDependency) async -> RefreshResult<InnerDependency>,
        updateOuter: () async -> RefreshResult<OuterDependency>
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
            await innerRunner.reset()
            return await updateOuter()
        }
        .flatMap { $0 }
    }
    
    
}