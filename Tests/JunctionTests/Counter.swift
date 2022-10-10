
import Foundation

/// A simple counting actor for debugging purposes.
actor Counter {
    
    var i = 0
    
    init(i: Int = 0) {
        self.i = i
    }
    
    /// Increments the count by one.
    func increment() {
        self.i = self.i + 1
    }
    
    /// Gets the current count.
    func getCount() -> Int {
        return i
    }
}
