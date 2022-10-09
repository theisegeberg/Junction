
import Foundation

public enum FakeResponse {
    case unauthorised
    case ok(String)
    case updatedToken(UUID)
}

public struct TimedToken:Codable {
    public let token:UUID
    private let created:Date
    private let timeToLive:TimeInterval
    
    init(token: UUID = .init(), created: Date = .init(), timeToLive:TimeInterval = 0.3) {
        self.token = token
        self.created = created
        self.timeToLive = timeToLive
    }
    
    private var isValid:Bool {
        created.distance(to: .init()) < timeToLive
    }
    
    func validate(clientToken:UUID) -> Bool {
        isValid && self.token == clientToken
    }
}

public actor FakeOauth {
    
    var refreshToken:TimedToken? = nil
    var accessToken:TimedToken? = nil
    var password:String = "PWD"
    
    public func login(password:String) async -> TimedToken {
        print("🦑 LOGIN CALLED")
        try! await Task.sleep(nanoseconds: UInt64.random(in: 10_000_000...200_000_000))
        let refreshToken:TimedToken = TimedToken(timeToLive: 3)
        self.refreshToken = refreshToken
        self.accessToken = nil
        return refreshToken
    }
    
    public func logout() {
        print("🦑 LOGOUT CALLED")
        self.refreshToken = nil
        self.accessToken = nil
    }
    
    public func refresh(clientRefreshToken:UUID) async -> FakeResponse {
        print("🦑 REFRESH CALLED")
        guard let ownRefreshToken = refreshToken,
              ownRefreshToken.validate(clientToken: clientRefreshToken)
        else {
            print("🦑 REFRESH UNAUTHORISED")
            try! await Task.sleep(nanoseconds: UInt64.random(in: 10_000_000...200_000_000))
            return .unauthorised
        }
        print("🦑 REFRESH NEW ACCESS TOKEN GRANTED")
        try! await Task.sleep(nanoseconds: UInt64.random(in: 10_000_000...200_000_000))
        let newAccessToken = TimedToken()
        self.accessToken = newAccessToken
        return .updatedToken(newAccessToken.token)
    }
    
    public func getResource(clientAccessToken:UUID) async -> FakeResponse {
        print("🦑 RESOURCE CALLED")
        guard let ownAcccessToken = accessToken,
              ownAcccessToken.validate(clientToken: clientAccessToken) else {
            print("🦑 RESOURCE UNAUTHORISED")
            try! await Task.sleep(nanoseconds: UInt64.random(in: 10_000_000...200_000_000))
            return .unauthorised
        }
        print("🦑 RESOURCE OK")
        try! await Task.sleep(nanoseconds: UInt64.random(in: 10_000_000...200_000_000))
        return .ok("<html><body>Hello world!</body></html>")
    }
    
}
