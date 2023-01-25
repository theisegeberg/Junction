import Foundation

public extension Task where Failure == Never, Success == Failure {
    
    static func retry<Success:Sendable>(
        configuration:RetryConfiguration,
        task:(_ retryIteration:Int, _ time:TimeInterval) async throws -> (RetryResult<Success>)
    ) async throws -> Success {
        try await retry(
            configuration: configuration,
            retryIteration: 0,
            started: Date(),
            task: task
        )
    }
    
    private static func retry<Success:Sendable>(
        configuration:RetryConfiguration,
        retryIteration:Int,
        started:Date,
        task:(_ retryIteration:Int, _ time:TimeInterval) async throws -> (RetryResult<Success>)
    ) async throws -> Success {
        guard configuration.shouldRetry(atRetryIteration: retryIteration) else {
            throw RetryError.maximumRetriesReached
        }
        do {
            let nextSleep = configuration.getNextSleep(forRetryIteration: retryIteration)
            try await Task.sleep(
                nanoseconds: nextSleep
            )
            switch try await task(retryIteration, Date().timeIntervalSince(started)) {
                case .success(let success):
                    return success
                case .retry:
                    return try await retry(
                        configuration: configuration,
                        retryIteration: retryIteration + 1,
                        started: started,
                        task: task
                    )
            }
        } catch is CancellationError {
            throw RetryError.cancelled
        }
        
    }
}
