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

        XCTAssertEqual(successResult, .success(randomNumber))
    }

    func testIncrementingUpdateSuccess() async throws {
        let runner = Dependency<Int>()

        var temporarilyRefreshedDependency = 0
        let expectedNumber = 3
        let incrementingResult = try await runner.run(task: { dependency in
            XCTAssertLessThanOrEqual(dependency, expectedNumber)
            if dependency == expectedNumber {
                return .success(dependency)
            } else {
                return .dependencyRequiresRefresh
            }
        }, refreshDependency: { _ in
            temporarilyRefreshedDependency = temporarilyRefreshedDependency + 1
            XCTAssertLessThanOrEqual(temporarilyRefreshedDependency, expectedNumber)
            return .refreshedDependency(temporarilyRefreshedDependency)
        })

        XCTAssertEqual(incrementingResult, .success(expectedNumber))
    }

    func testUpdateWithRefreshFailure1() async throws {
        let runner = Dependency<Int>()

        let failedResult = try await runner.run(task: { _ -> TaskResult<Int> in
            .dependencyRequiresRefresh
        }, refreshDependency: { _ in
            .failedRefresh
        })

        XCTAssertEqual(failedResult, .failedRefresh)
    }

    func testUpdateWithRefreshFailure2() async throws {
        let runner = Dependency<Int>()

        let failedResult = try await runner.run(task: { _ -> TaskResult<Int> in
            .success(10)
        }, refreshDependency: { _ in
            .failedRefresh
        })

        XCTAssertEqual(failedResult, .failedRefresh)
    }

    func testTimeoutFailure() async throws {
        let runner = Dependency<Int>()

        let timeout = TimeInterval.random(in: 1 ..< 2)
        let successResult = Int.random(in: 0 ... Int.max)
        let timeoutFailureResult = try await runner.run(task: { dependency -> TaskResult<Int> in
            .success(dependency)
        }, refreshDependency: { _ in
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            return .refreshedDependency(successResult)
        },
        timeout: timeout)

        XCTAssertEqual(timeoutFailureResult, .timeout)
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
        XCTAssertEqual(timeoutSuccess, .success(successResult))
    }

    func testContextObject() async throws {
        let runner = Dependency<Int>()

        class Context: DependencyProxy {
            typealias Success = String
            typealias Dependency = Int

            let expectedNumber: Int = 3
            var temporarilyRefreshedDependency: Int = 0

            func timeout() -> TimeInterval? {
                nil
            }

            func run(_ dependency: Int) async throws -> (Junction.TaskResult<String>) {
                XCTAssertLessThanOrEqual(dependency, expectedNumber)
                if dependency == expectedNumber {
                    return .success("\(dependency)")
                } else {
                    return .dependencyRequiresRefresh
                }
            }

            func refresh(failingDependency: Int?) async throws -> (RefreshResult<Int>) {
                temporarilyRefreshedDependency = temporarilyRefreshedDependency + 1
                XCTAssertLessThanOrEqual(temporarilyRefreshedDependency, expectedNumber)
                return .refreshedDependency(temporarilyRefreshedDependency)
            }
            
        }

        let context = Context()

        let incrementingResult = try await runner.run(context)

        XCTAssertEqual(incrementingResult, .success("\(context.expectedNumber)"))
    }
}
