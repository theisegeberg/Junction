import XCTest
@testable import Junction

final class DependencyTests: XCTestCase {
    func testSuccess() async throws {
        let dependency = Dependency<Int>(configuration: .init(threadSleepNanoSeconds: 100_000_000))
        let randomNumber = Int.random(in: 0 ... Int.max)

        let successResult = try await Task.inject(dependency: dependency) { dependency,_ in
            .success(dependency)
        } refresh: { _,_ in
            .refreshedDependency(randomNumber)
        }

        XCTAssertEqual(successResult, randomNumber)
    }
    
    func testCancellation() async throws {
        let dependency = Dependency<Int>(configuration: .default)
        let randomNumber = Int.random(in: 0 ... Int.max)
        let task = Task { () throws -> Int in
            let successResult = try await Task.inject(dependency: dependency) { dependency,_ in
                try await Task.sleep(nanoseconds: 1_000_000)
                return .success(dependency)
            } refresh: { _,_ in
                try await Task.sleep(nanoseconds: 1_000_000)
                return .refreshedDependency(randomNumber)
            }
            return successResult
        }
        task.cancel()
        let expectation = XCTestExpectation()
        do {
            let _ = try await task.value
            XCTFail("Should not get to here")
        } catch is CancellationError {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    actor OutsideValue: Sendable {
        var value: Int

        init(value: Int) {
            self.value = value
        }

        func increment() {
            value = value + 1
        }

        func getValue() -> Int {
            value
        }
    }

    func testIncrementingUpdateSuccess() async throws {
        let dependency = Dependency<Int>(configuration: .default)

        let temporarilyRefreshedDependency = OutsideValue(value: 0)

        let expectedNumber = 3
        let incrementingResult = try await Task.inject(dependency: dependency) { dependency,_ in
            XCTAssertLessThanOrEqual(dependency, expectedNumber)
            if dependency == expectedNumber {
                return .success(dependency)
            } else {
                return .dependencyRequiresRefresh
            }
        } refresh: { _,_ in
            await temporarilyRefreshedDependency.increment()
            let value = await temporarilyRefreshedDependency.value
            XCTAssertLessThanOrEqual(value, expectedNumber)
            return .refreshedDependency(await temporarilyRefreshedDependency.value)
        }

        XCTAssertEqual(incrementingResult, expectedNumber)
    }

    func testUpdateWithRefreshFailure1() async throws {
        let dependency = Dependency<Int>(configuration: .default)

        let expectation = XCTestExpectation()
        do {
            let _ = try await Task.inject(dependency: dependency, task: { _,_ -> TaskResult<Int> in
                .dependencyRequiresRefresh
            }, refresh: { _,_ in
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
        let dependency = Dependency<Int>(configuration: .default)

        let tasks = Int.random(in: 0 ..< 100)
        var expectations = [XCTestExpectation]()

        for _ in 0 ..< tasks {
            let expectation = XCTestExpectation()
            expectations.append(expectation)
            Task {
                do {
                    let _ = try await Task.inject(dependency: dependency, task: { _,_ -> TaskResult<Int> in
                        fatalError("Should never occur")
                    }, refresh: { _,_ in
                        .failedRefresh
                    })
                } catch {
                    if let error = error as? DependencyError, error.code == .failedRefresh {
                        expectation.fulfill()
                    }
                }
            }
        }
        wait(for: expectations, timeout: 1)
    }

    func testRefresh() async throws {
        let dependency = Dependency<Int>(configuration: .init(threadSleepNanoSeconds: 100_000_000))

        let tasks = Int.random(in: 1 ..< 20)
        var expectations = [XCTestExpectation]()

        for _ in 0 ..< tasks {
            let expectation = XCTestExpectation()
            expectations.append(expectation)
            Task {
                do {
                    let result = try await Task.inject(dependency: dependency, task: { intDependency,_ -> TaskResult<Int> in
                        try await Task.sleep(nanoseconds: 50000 + UInt64.random(in: 100_000 ..< 200_000))
                        if intDependency < 10 {
                            return .dependencyRequiresRefresh
                        }
                        return .success(intDependency)
                    }, refresh: { lastDependency,_ in
                        try await Task.sleep(nanoseconds: 50000 + UInt64.random(in: 400_000 ..< 500_000))
                        return .refreshedDependency((lastDependency ?? 0) + 1)
                    })
                    XCTAssertEqual(result, 10)
                    expectation.fulfill()
                } catch {
                    fatalError()
                }
            }
        }
        wait(for: expectations, timeout: 1)
    }
    
    func testMaximumRefreshFailure() async throws {
        let dependency = Dependency<Int>(configuration: .init(threadSleepNanoSeconds: 100_000_000))

        try await dependency.reset()
        let _ = try await Task.inject(dependency: dependency, task: { intDependency,_ -> TaskResult<Int> in
            try await Task.sleep(nanoseconds: 50000 + UInt64.random(in: 100_000 ..< 200_000))
            if intDependency < 10 {
                return .dependencyRequiresRefresh
            }
            return .success(intDependency)
        }, refresh: { lastDependency,_ in
            try await Task.sleep(nanoseconds: 50000 + UInt64.random(in: 400_000 ..< 500_000))
            return .refreshedDependency((lastDependency ?? 0) + 1)
        })
        
        try await dependency.reset()
        let _ = try await Task.inject(dependency: dependency, task: { intDependency,_ -> TaskResult<Int> in
            try await Task.sleep(nanoseconds: 50000 + UInt64.random(in: 100_000 ..< 200_000))
            if intDependency < 10 {
                return .dependencyRequiresRefresh
            }
            return .success(intDependency)
        }, refresh: { lastDependency,_ in
            try await Task.sleep(nanoseconds: 50000 + UInt64.random(in: 400_000 ..< 500_000))
            return .refreshedDependency((lastDependency ?? 0) + 1)
        })

        let _ = try await Task.inject(dependency: dependency, task: { intDependency,_ -> TaskResult<Int> in
            try await Task.sleep(nanoseconds: 50000 + UInt64.random(in: 100_000 ..< 200_000))
            if intDependency < 9 {
                return .dependencyRequiresRefresh
            }
            return .success(intDependency)
        }, refresh: { lastDependency,_ in
            try await Task.sleep(nanoseconds: 50000 + UInt64.random(in: 400_000 ..< 500_000))
            return .refreshedDependency((lastDependency ?? 0) + 1)
        })
        
    }

//    func testTimeoutFailure() async throws {
//        let dependency = Dependency<Int>(configuration: .init(threadSleepNanoSeconds: 100_000_000, timeout: 1.5, maximumRefreshes: 4))
//
//        let expectation = XCTestExpectation()
//
//        do {
//            let successResult = Int.random(in: 0 ... Int.max)
//            let _ = try await Task.inject(
//                dependency: dependency,
//                task: { _,_ -> TaskResult<Int> in
//                    XCTFail("Should not happen")
//                    fatalError("Should never occur")
//                }, refresh: { _,_ in
//                    try await Task.sleep(nanoseconds: UInt64(1.5 * 1_000_000_000))
//                    return .refreshedDependency(successResult)
//                }
//            )
//        } catch {
//            if let error = error as? DependencyError, error.code == .timeout {
//                expectation.fulfill()
//            }
//        }
//        wait(for: [expectation], timeout: 0.1)
//    }

    func testTimeoutSuccess() async throws {
        let dependency = Dependency<Int>(configuration: .init(threadSleepNanoSeconds: 100_000_000))

        let successResult = Int.random(in: 0 ... Int.max)
        let timeoutSuccess = try await Task.inject(
            dependency: dependency, task: { dependency,_ -> TaskResult<Int> in
            .success(dependency)
        }, refresh: { _,_ in
            try await Task.sleep(nanoseconds: UInt64(1.5 * 0.8 * 1_000_000_000))
            return .refreshedDependency(successResult)
        })
        XCTAssertEqual(timeoutSuccess, successResult)
    }

    func testCriticalError() async throws {
        let dependency = Dependency<Int>(configuration: .default)

        struct TestError: Error {
            let value: String
        }
        let randomString = "Hello world"
        let taskCount = Int.random(in: 10 ... 20)
        let counterOfTasksClaimingToBeOriginalError = Counter()
        var expectations = [XCTestExpectation]()

        for _ in 0 ... taskCount {
            let expectation = XCTestExpectation()
            expectations.append(expectation)

            Task {
                do {
                    let successResult = Int.random(in: 0 ... Int.max)
                    let _ = try await Task.inject(
                        dependency: dependency,
                        task: { _,_ -> TaskResult<Int> in
                            try await Task.sleep(nanoseconds: 10_000 + UInt64.random(in: 10_000 ..< 20_000))
                            return .criticalError(underlyingError: TestError(value: randomString))
                        }, refresh: { _,_ in
                            .refreshedDependency(successResult)
                        }
                    )
                } catch {
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

        try await Task.sleep(nanoseconds: 1_000_000_000)
        let finalCountOfOriginalErrorClaims = await counterOfTasksClaimingToBeOriginalError.i
        wait(for: expectations, timeout: 10)
        XCTAssertEqual(finalCountOfOriginalErrorClaims, 1)
    }

    func testError() {
        XCTAssertEqual(DependencyError(code: .critical(wasThrownByThisTask: true, error: nil)), DependencyError(code: .critical(wasThrownByThisTask: false, error: nil)))
        XCTAssertEqual(DependencyError(code: .failedRefresh), DependencyError(code: .failedRefresh))
    }
}
