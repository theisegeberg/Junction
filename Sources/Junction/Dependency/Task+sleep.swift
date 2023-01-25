
import Foundation

extension Task {
    
    /// Sleeps the task for a number of nanoseconds as long as the while condition is true.
    /// - Parameters:
    ///   - while: Condition that must be true for the `Task` to keep on sleeping.
    ///   - nanoseconds: Number of nanoseconds between each test of the while condition.
    ///   sleep method.
    static func sleep(`while` sleepWhile: @autoclosure () -> Bool, nanoseconds:UInt64) async throws where Success == Never, Failure == Success {
        while sleepWhile() {
            try await sleep(nanoseconds: nanoseconds)
            await yield()
        }
    }
    
    
}
