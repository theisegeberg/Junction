
import Foundation

class VersionStore<VersionType> {
    private var latest: VersionType?
    private var version: Int
    private var isInvalid: Bool
    
    init(dependency: VersionType? = nil) {
        latest = dependency
        version = 0
        isInvalid = false
    }
    
    func newVersion(_ newVersion: VersionType?) {
        if version == Int.max {
            version = 0
        }
        isInvalid = false
        version = version + 1
        latest = newVersion
    }
    
    func getVersion() -> Int {
        version
    }
    
    func getLatest() -> VersionType? {
        latest
    }
    
    func reset() {
        latest = nil
        version = 0
        isInvalid = false
    }
    
    func invalidate() {
        isInvalid = true
    }
    
    func getIsInvalid() -> Bool {
        isInvalid
    }
}
