

import Foundation

actor Counter {
    var i = 0
    init(i: Int = 0) {
        self.i = i
    }
    
    func increment() {
        self.i = self.i + 1
    }
    
    func getI() -> Int {
        return i
    }
}
