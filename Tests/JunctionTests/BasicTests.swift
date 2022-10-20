@testable import Junction
import XCTest

final class BasicTests: XCTestCase {
    func testSuccess() async throws {
        let runner = Dependency<Int>()
        let randomNumber = Int.random(in: 0 ... Int.max)

        let successResult = try await runner.run { dependency in
            .success(dependency)
        } refreshDependency: { _ in
            .refreshedDependency(randomNumber)
        }

        XCTAssertEqual(successResult, randomNumber)
    }

    actor OutsideValue:Sendable {
        var value:Int
        
        init(value: Int) {
            self.value = value
        }
        
        func increment() {
            value = value + 1
        }
        
        func getValue() -> Int {
            return value
        }
    }
    
    func testIncrementingUpdateSuccess() async throws {
        let runner = Dependency<Int>()
        
        let temporarilyRefreshedDependency = OutsideValue(value: 0)
        
        let expectedNumber = 3
        let incrementingResult = try await runner.run(task: { dependency in
            XCTAssertLessThanOrEqual(dependency, expectedNumber)
            if dependency == expectedNumber {
                return .success(dependency)
            } else {
                return .dependencyRequiresRefresh
            }
        }, refreshDependency: { _ in
            await temporarilyRefreshedDependency.increment()
            let value = await temporarilyRefreshedDependency.value
            XCTAssertLessThanOrEqual(value, expectedNumber)
            return .refreshedDependency(await temporarilyRefreshedDependency.value)
        })

        XCTAssertEqual(incrementingResult, expectedNumber)
    }

    func testUpdateWithRefreshFailure1() async throws {
        let runner = Dependency<Int>()

        let expectation = XCTestExpectation()
        do {
            let _ = try await runner.run(task: { _ -> TaskResult<Int> in
                .dependencyRequiresRefresh
            }, refreshDependency: { _ in
                .failedRefresh
            })
        } catch {
            if let error = error as? DependencyError, error.code == .failedRefresh {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 0.1)
    }

    func testUpdateWithRefreshFailure2() async throws {
        let runner = Dependency<Int>()

        let expectation = XCTestExpectation()
        do {
            let _ = try await runner.run(task: { _ -> TaskResult<Int> in
                .success(10)
            }, refreshDependency: { _ in
                .failedRefresh
            })
        } catch {
            if let error = error as? DependencyError, error.code == .failedRefresh {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 0.1)
    }

    func testTimeoutFailure() async throws {
        let runner = Dependency<Int>()

        let expectation = XCTestExpectation()

        do {
            let timeout = TimeInterval.random(in: 1 ..< 2)
            let successResult = Int.random(in: 0 ... Int.max)
            let _ = try await runner.run(
                task: { dependency -> TaskResult<Int> in
                    .success(dependency)
                }, refreshDependency: { _ in
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    return .refreshedDependency(successResult)
                },
                timeout: timeout
            )
        } catch {
            if let error = error as? DependencyError, error.code == .timeout {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 0.1)
    }

    func testTimeoutSuccess() async throws {
        let runner = Dependency<Int>()

        let timeout = TimeInterval.random(in: 1 ..< 2)
        let successResult = Int.random(in: 0 ... Int.max)
        let timeoutSuccess = try await runner.run(task: { dependency -> TaskResult<Int> in
            .success(dependency)
        }, refreshDependency: { _ in
            try await Task.sleep(nanoseconds: UInt64(timeout * 0.8 * 1_000_000_000))
            return .refreshedDependency(successResult)
        },
        timeout: timeout)
        XCTAssertEqual(timeoutSuccess, successResult)
    }

    func testCriticalError() async throws {
        let runner = Dependency<Int>()

        struct TestError: Error {
            let value: String
        }
        let randomString = "Hello world"
        let taskCount = Int.random(in: 3 ... 100)
        let counterOfTasksClaimingToBeOriginalError = Counter()
        var expectations = [XCTestExpectation]()

        for _ in 0 ... taskCount {
            let expectation = XCTestExpectation()
            expectations.append(expectation)

            Task {
                do {
                    let timeout = TimeInterval.random(in: 1 ..< 2)
                    let successResult = Int.random(in: 0 ... Int.max)
                    let _ = try await runner.run(
                        task: { _ -> TaskResult<Int> in
                            try await Task.sleep(nanoseconds: 100_000 + UInt64.random(in: 100_000 ..< 200_000))
                            return .criticalError(underlyingError: TestError(value: randomString))
                        }, refreshDependency: { _ in
                            .refreshedDependency(successResult)
                        },
                        timeout: timeout
                    )
                } catch {
                    dump(error)
                    if let error = error as? DependencyError {
                        if case let .critical(wasThrownByThisTask, underlyingError) = error.code {
                            if wasThrownByThisTask {
                                await counterOfTasksClaimingToBeOriginalError.increment()
                            }
                            if let testError = underlyingError as? TestError {
                                XCTAssertEqual(testError.value, randomString)
                                expectation.fulfill()
                            }
                        }
                    }
                }
            }
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        let finalCountOfOriginalErrorClaims = await counterOfTasksClaimingToBeOriginalError.i
        wait(for: expectations, timeout: 5)
        XCTAssertEqual(finalCountOfOriginalErrorClaims, 1)
    }
}
