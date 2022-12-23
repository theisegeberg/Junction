
import Foundation

extension Task {
    
    /// Sleeps the task for a number of nanoseconds as long as the while condition is true, also performs a
    /// test at every loop (after the nanoseconds passed).
    /// - Parameters:
    ///   - while: Condition that must be true for the `Task` to keep on sleeping.
    ///   - nanoseconds: Number of nanoseconds between each test of the while condition.
    ///   - testing: A closure that's run on every loop, used to throw potential errors from within the
    ///   sleep method.
    static func sleep(`while` sleepWhile: @autoclosure () -> Bool, nanoseconds:UInt64, testing:() async throws -> ()) async throws where Success == Never, Failure == Success {
        while sleepWhile() {
            try await sleep(nanoseconds: nanoseconds)
            try await testing()
            await yield()
        }
    }
    
    
}
