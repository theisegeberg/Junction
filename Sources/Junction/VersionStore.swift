
import Foundation

class VersionStore<VersionType> {
    private var latest: VersionType?
    private var version: Int
    private var isValid: Bool

    init(dependency: VersionType? = nil) {
        latest = dependency
        version = 0
        isValid = true
    }

    func newVersion(_ newVersion: VersionType?) {
        if version == Int.max {
            version = 0
        }
        isValid = true
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
        isValid = true
    }

    func invalidate() {
        isValid = false
    }

    func getIsValid() -> Bool {
        isValid
    }
}
