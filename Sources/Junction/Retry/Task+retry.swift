import Foundation

public extension Task where Failure == Never, Success == Failure {
    
    static func retry<Success:Sendable>(
        configuration:RetryConfiguration,
        task:(_ retryIteration:Int, _ totalSleepTimeNanoseconds:UInt64) async throws -> (RetryResult<Success>)
    ) async throws -> Success {
        try await retry(
            configuration: configuration,
            retryIteration: 0,
            totalSleepTimeNanoseconds: 0,
            task: task
        )
    }
    
    private static func retry<Success:Sendable>(
        configuration:RetryConfiguration,
        retryIteration:Int,
        totalSleepTimeNanoseconds:UInt64,
        task:(_ retryIteration:Int, _ totalSleepTimeNanoseconds:UInt64) async throws -> (RetryResult<Success>)
    ) async throws -> Success {
        guard configuration.shouldRetry(atRetryIteration: retryIteration) else {
            throw RetryError.maximumRetriesReached
        }
        do {
            let nextSleep = configuration.getNextSleep(forRetryIteration: retryIteration)
            try await Task.sleep(
                nanoseconds: nextSleep
            )
            let totalSleepSoFar = totalSleepTimeNanoseconds + nextSleep
            switch try await task(retryIteration, totalSleepSoFar) {
                case .success(let success):
                    return success
                case .retry:
                    return try await retry(
                        configuration: configuration,
                        retryIteration: retryIteration + 1,
                        totalSleepTimeNanoseconds: totalSleepSoFar,
                        task: task
                    )
            }
        } catch is CancellationError {
            throw RetryError.cancelled
        }
        
    }
}
