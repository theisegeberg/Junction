# Junction
Try - refresh - retry library.

Made to withstand the hard vacuum of concurrency and remote state.

I originally wrote this code in `Combine` in a library called `Sidetrack`,
but I was delicately told that it held some race conditions I wasn't aware of.
This is hardened somewhat, but be aware that these things are extremely hard
to test, and the nature of a library like this means it is almost impossible
to prove rationally. That being said I wrote a lot of tests for it, some to
prove it empirically.

And warning: This is purely a hobby project, I don't provide any support for it.
Take it as it is, or roll your own. After writing it I've been inspired to pursue
another route which is more akin to message passing to solve the problem. The elegance
of this solution is "sort of cute and fun", but it suffers from being hard to
prove and hard to debug.

While it requires a lot more code, and completely different architecture I think
I would propose an architecture that looks more like even more asynchronous 
message passing. Where you pass in a call, and then you're called back when
it is completed. This would remove some of the hard to read parts in this library.

## Basic usage

I'll describe via one of the tests written. Read the below code first and then
continue here... Alright, well that seems pretty simple, what's so great about
that? Here's the kicker, if this method is called on concurrently, then when the 
first task returns `.dependencyRequiresRefresh` it will start the second closure.
But any subsequent task returning that won't. It will instead just be put in a
waiting pattern, till the second closure has been run **!just once!** and then
it will be retried with the new dependency. And that's all. There are six plantUML
sequence diagrams in the repo to describe the problems and solutions. 

```Swift
// This is a helper that keeps track of a single value.
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
    // 1. We create a dependency on an `Int`
    let dependency = Dependency<Int>(configuration: .default)
    
    let temporarilyRefreshedDependency = OutsideValue(value: 0)
    
    // 2. This is our target number. We want the dependency to arrive at that.
    let expectedNumber = 3
    
    // 3. We call `Task.inject` to start a request based on this dependency.
    let incrementingResult = try await Task.inject(dependency: dependency) { dependency,_ in
    
        // 4. The first closure is the code that needs the dependency. In this case
        // It'll return `.dependencyRequiresRefresh` for all numbers not 3.
        // When it returns `.success` with a value the entire `Task.inject` will
        // also return that success value.
        // When it returns `.dependencyRequiresRefresh` then the block of code
        // below will be run.
        XCTAssertLessThanOrEqual(dependency, expectedNumber)
        if dependency == expectedNumber {
            return .success(dependency)
        } else {
            return .dependencyRequiresRefresh
        }
    } refresh: { _,_ in
        // 5. This is the code that creates or fetches the dependency from somewhere
        // else. In this case we just increment it. That means it'll go to 1, 2, 3
        // each time. Bouncing back and forth between this closure and the one above.
        await temporarilyRefreshedDependency.increment()
        let value = await temporarilyRefreshedDependency.value
        XCTAssertLessThanOrEqual(value, expectedNumber)
        return await temporarilyRefreshedDependency.value
    }
    
    XCTAssertEqual(incrementingResult, expectedNumber)
}
```

