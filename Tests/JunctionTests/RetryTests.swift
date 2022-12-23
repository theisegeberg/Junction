import XCTest
@testable import Junction

final class RetryTests: XCTestCase {
    func testRetryConfigurationImmediate1() {
        let configuration = RetryConfiguration(maximumRetries: 1, strategy: .immediate)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 0), 0)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 1), 0)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 50), 0)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: -1), 0)
        XCTAssertEqual(configuration.shouldRetry(atRetryIteration: 0), true)
        XCTAssertEqual(configuration.shouldRetry(atRetryIteration: 1), false)
        XCTAssertEqual(configuration.shouldRetry(atRetryIteration: -1), false)
    }
    
    func testRetryConfigurationImmediate2() {
        let configuration = RetryConfiguration(maximumRetries: 2, strategy: .immediate)
        
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 0), 0)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 1), 0)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 2), 0)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: -1), 0)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: .max), 0)
        XCTAssertEqual(configuration.shouldRetry(atRetryIteration: 0), true)
        XCTAssertEqual(configuration.shouldRetry(atRetryIteration: 1), true)
        XCTAssertEqual(configuration.shouldRetry(atRetryIteration: 2), false)
        XCTAssertEqual(configuration.shouldRetry(atRetryIteration: -1), false)
    }
    
    func testRetryConfigurationFixed1() {
        let configuration = RetryConfiguration(maximumRetries: 3, strategy: .fixed(nanoseconds: 10))
        
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 0), 0)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 1), 10)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 2), 10)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 3), 10)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: -1), 0)
    }
    
    func testRetryConfigurationLinearBackOff() {
        let configuration = RetryConfiguration(maximumRetries: 4, strategy: .linearBackOff(nanoseconds: 10))
        
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 0), 0)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 1), 10)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 2), 20)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 3), 30)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 4), 40)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: -1), 0)
    }

    func testRetryConfigurationExponentialBackoff() {
        let configuration = RetryConfiguration(maximumRetries: 6, strategy: .exponentialBackOff(nanoseconds: 10))
        
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 0), 0)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 1), 10)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 2), 20)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 3), 40)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 4), 80)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 5), 160)
        XCTAssertNotEqual(configuration.getNextSleep(forRetryIteration: 5), 260)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: 6), 320)
        XCTAssertEqual(configuration.getNextSleep(forRetryIteration: -1), 0)
    }
    
    func testRetrySuccessImmediate1() async throws {
        
        let retries:Int = Int.random(in: 20..<100)
        let expectationSuccess = XCTestExpectation()
        let expectationRetriesReached = XCTestExpectation()
        
        let retVal:Bool = try await Task.retry(
            configuration: .init(maximumRetries: UInt(retries + 1), strategy: .immediate)
        ) {
            retryIteration, sleep in
            guard retryIteration < retries else {
                expectationSuccess.fulfill()
                return .success(true)
            }
            if retryIteration == retries - 1 {
                expectationRetriesReached.fulfill()
            }
            if retryIteration >= retries {
                XCTFail()
            }
            return .retry
        }
        
        XCTAssertEqual(retVal, true)
        wait(for: [expectationSuccess,expectationRetriesReached], timeout: 10)
    }
    
    func testRetryMaximumRetriesImmediate() async throws {
        
        let retries:Int = Int.random(in: 20..<100)
        let expectationRetriesReached = XCTestExpectation(description: "Retries reached")
        let expectationErrorThrown = XCTestExpectation(description: "Error was thrown")
        
        let expectations = [expectationRetriesReached, expectationErrorThrown]
        
        do {
            let _:Bool = try await Task.retry(
                configuration: .init(maximumRetries: UInt(retries), strategy: .immediate)
            ) {
                retryIteration, sleep in
                guard retryIteration < retries + 10 else {
                    XCTFail()
                    fatalError()
                }
                if retryIteration == retries - 1 {
                    expectationRetriesReached.fulfill()
                }
                if retryIteration == retries {
                    XCTFail()
                }
                if retryIteration >= retries {
                    XCTFail()
                }
                return .retry
            }
            XCTFail()
        } catch RetryError.maximumRetriesReached {
            expectationErrorThrown.fulfill()
        }
        wait(for: expectations, timeout: 10)
    }
    
    func testRetryCancelImmediate() async throws {
        
        let retries:Int = Int.random(in: 20..<100)
        let expectationCancelThrown = XCTestExpectation(description: "Error was thrown")
        let expectations = [expectationCancelThrown]
        
        
        Task {
            let t = Task {
                do {
                    
                    let _:Bool = try await Task.retry(
                        configuration: .init(maximumRetries: UInt(retries), strategy: .immediate)
                    ) {
                        retryIteration, sleep in
                        XCTFail()
                        return .retry
                    }
                } catch RetryError.cancelled {
                    expectationCancelThrown.fulfill()
                }
            }
            t.cancel()
        }
        
        wait(for: expectations, timeout: 10)
    }
    
    func testRetryStrategies() async throws {
        
        let strategies:[RetryConfiguration.RetryStrategy] = [
            .immediate,
            .fixed(nanoseconds: UInt64.random(in: 20...30)),
            .linearBackOff(nanoseconds: UInt64.random(in: 20...30)),
            .exponentialBackOff(nanoseconds: UInt64.random(in: 20...30))
        ]
        
        for strategy in strategies {
            let retries:Int = Int.random(in: 10..<30)
            let expectationSuccess = XCTestExpectation(description: "Success")
            let expectationRetriesReached = XCTestExpectation(description: "Retries reached")
            let expectations = [expectationSuccess, expectationRetriesReached]
            
            let retVal:Bool = try await Task.retry(
                configuration: .init(maximumRetries: UInt(retries), strategy: strategy)
            ) {
                retryIteration, sleep in
                if retryIteration == retries - 1 {
                    expectationRetriesReached.fulfill()
                }
                guard retryIteration < retries - 1 else {
                    expectationSuccess.fulfill()
                    return .success(true)
                }
                
                if retryIteration >= retries {
                    XCTFail()
                }
                return .retry
            }
            XCTAssertEqual(retVal, true)
            wait(for: expectations, timeout: 2)
        }
        
    }

    

}
