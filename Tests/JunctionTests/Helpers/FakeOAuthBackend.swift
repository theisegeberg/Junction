
import Foundation

public enum FakeResponse {
    case unauthorised
    case ok(String)
    case updatedToken(UUID)
}

public struct TimedToken: Codable {
    public let token: UUID
    private let created: Date
    private let timeToLive: TimeInterval

    init(token: UUID = .init(), created: Date = .init(), timeToLive: TimeInterval = 0.3) {
        self.token = token
        self.created = created
        self.timeToLive = timeToLive
    }

    private var isValid: Bool {
        created.distance(to: .init()) < timeToLive
    }

    func validate(clientToken: UUID) -> Bool {
        isValid && token == clientToken
    }
}

actor Logger {
    var log: String = ""
    func log(_ message: String) {
        log.append("\n\(message)")
    }

    func printLog() {
        print(log)
    }
}

public class FakeOauth {
    var refreshToken: TimedToken?
    var accessToken: TimedToken?
    var password: String = "PWD"
    let logger: Logger = .init()

    public init() {}

    func log(_ message: String) {
        Task {
            await logger.log(message)
        }
    }

    public func login(password _: String) async -> TimedToken {
        log("🦑 LOGIN CALLED")
        try! await Task.sleep(nanoseconds: UInt64.random(in: 10_000_000 ... 1_000_000_000))
        let refreshToken = TimedToken(timeToLive: 3)
        self.refreshToken = refreshToken
        accessToken = nil
        log("🦑 LOGGED IN")
        return refreshToken
    }

    public func loginWithAccess(password _: String) async -> (TimedToken, TimedToken) {
        log("🦑 LOGIN CALLED")
        try! await Task.sleep(nanoseconds: UInt64.random(in: 10_000_000 ... 200_000_000))
        let refreshToken = TimedToken(timeToLive: 3)
        let accessToken = TimedToken(timeToLive: 0.5)
        self.refreshToken = refreshToken
        self.accessToken = accessToken
        log("🦑 LOGGED IN")
        return (refreshToken, accessToken)
    }

    public func logout() {
        log("🦑 LOGOUT CALLED")
        refreshToken = nil
        accessToken = nil
    }

    public func refresh(clientRefreshToken: UUID) async -> FakeResponse {
        log("🦑 REFRESH CALLED")
        guard let ownRefreshToken = refreshToken,
              ownRefreshToken.validate(clientToken: clientRefreshToken)
        else {
            try! await Task.sleep(nanoseconds: UInt64.random(in: 10_000_000 ... 300_000_000))
            log("🦑 REFRESH UNAUTHORISED")
            return .unauthorised
        }
        log("🦑 REFRESH NEW ACCESS TOKEN GRANTED")
        try! await Task.sleep(nanoseconds: UInt64.random(in: 10_000_000 ... 300_000_000))
        let newAccessToken = TimedToken()
        accessToken = newAccessToken
        return .updatedToken(newAccessToken.token)
    }

    public func getResource(clientAccessToken: UUID) async -> FakeResponse {
        log("🦑 RESOURCE CALLED")
        guard let ownAcccessToken = accessToken,
              ownAcccessToken.validate(clientToken: clientAccessToken)
        else {
            log("🦑 RESOURCE UNAUTHORISED")
            try! await Task.sleep(nanoseconds: UInt64.random(in: 10_000_000 ... 300_000_000))
            return .unauthorised
        }
        log("🦑 RESOURCE OK")
        try! await Task.sleep(nanoseconds: UInt64.random(in: 10_000_000 ... 300_000_000))
        return .ok("<html><body>Hello world!</body></html>")
    }

    public func printLog() {
        Task {
            await logger.printLog()
        }
    }
}
