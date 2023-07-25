# Junction
Try - refresh - retry library.

Made to withstand the hard vacuum of concurrency and remote state.

## The problem

I wrote this code to solve a very specific problem:
Remote authoritative state in an multi-threaded client.

An example of this could be a remote access token that can suddenly
go stale. Imagine having a refresh token that can be used to get
an access token. But there's a catch: The access token can get invalidated
and further it WILL get invalidated when you get a new access token.

This is not an imagined scenario this exists in some very hardened 
versions of OIDC.

If the client runs several concurrent network requests then there
a specific race condition can occur where two threads both perform
a request with an invalid access token. Both will need to refresh the
token in order to get a new access token. But the threads do not
have any means of communication. In traditional OIDC this isn't a problem
because you can have multiple valid access tokens. But when you can't
the second thread will immediately invalidate the new access token 
created by the first thread, and this dance will go on till the end
of time. 

In order to fix this I wrote a "Junction": A piece of code that
sits in between all requests performed. It is based on the idea
of a generic dependency. This is required to execute the network request,
in our example it would be a string (an access token). The call
to junction is performed via `Task.inject`. It takes two closures.

The first closure utilises the dependency/access token. In practice 
this code would live only at one place inside the networking layer.
This closure returns a TaskResult. If the return value is:
TaskResult.dependencyRequiresRefresh
Then the second closure will be run. And then the first closure will
get retried with the new refreshed dependency.

The second is the code required to update the dependency. In our
example this would be code that uses a refresh token to get an
access token.

`Task.inject` will return the final result of the request.

## The magic

The above may seem a bit trivial. But the magic is that all requests
coming in while the dependency is refreshing will be put in a holding
pattern. Also all ongoing requests that result in a required refresh
will not result in a refresh, instead these will get requeued and run
again.

There's a strong guarantee that the refresh closure (the second closure)
is only running on one thread at any single moment. And this is not done
with GDC, it's done with Swifts structured concurrency.

You can explore the problem this code solves further by reading 
the Example[N].puml files.


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

