import Foundation

public struct RetryConfiguration:Codable {
    public enum RetryStrategy:Codable {
        case immediate
        case fixed(nanoseconds:UInt64)
        case linearBackOff(nanoseconds:UInt64)
        case exponentialBackOff(nanoseconds:UInt64)
    }
    private let maximumRetries:Int
    private let strategy:RetryStrategy
    
    public init(maximumRetries: UInt, strategy: RetryStrategy) {
        self.maximumRetries = (maximumRetries >= Int.max) ? Int.max : Int(maximumRetries)
        self.strategy = strategy
    }
    
    func getNextSleep(forRetryIteration retryIteration:Int) -> UInt64 {
        guard retryIteration > 0 else {
            return 0
        }
        switch strategy {
            case .immediate:
                return 0
            case .fixed(let nanoseconds):
                return nanoseconds
            case .linearBackOff(let nanoseconds):
                return nanoseconds * UInt64(retryIteration)
            case .exponentialBackOff(let nanoseconds):
                func pow<T: BinaryInteger>(_ base: T, _ power: T) -> T {
                    func expBySq(_ y: T, _ x: T, _ n: T) -> T {
                        precondition(n >= 0)
                        if n == 0 {
                            return y
                        } else if n == 1 {
                            return y * x
                        } else if n.isMultiple(of: 2) {
                            return expBySq(y, x * x, n / 2)
                        } else { // n is odd
                            return expBySq(y * x, x * x, (n - 1) / 2)
                        }
                    }
                    return expBySq(1, base, power)
                }
                return UInt64(pow(2, retryIteration - 1)) * nanoseconds
        }
    }
    
    func shouldRetry(atRetryIteration retryIteration:Int) -> Bool {
        retryIteration < maximumRetries && retryIteration >= 0
    }
    
    public static let once = Self.init(maximumRetries: 1, strategy: .fixed(nanoseconds: 250_000_000))
    
    public static let webRequest = Self.init(maximumRetries: 3, strategy: .exponentialBackOff(nanoseconds: 500_000_000))
}
