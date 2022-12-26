
# TODO:
Make a new kind of retry that loops through a set of values trying them each on if they fail.

# The problem
Imagine this: To access a resource through an API you need an access token. That access token can only
be gotten by using a refresh token. The refresh token requires the user to input its username and password.
There's a catch though, the refresh token can only be used once. On top of that all requests to the API should
happen concurrently, and we're not allowed to preemptively fetch access tokens or refresh tokens (because
we're #hardcore).

This might sound trivial. But I'll point out two problems here:

The first problem is trivial: Each time the server rejects our access token, we need to request a new one
with our refresh token. Right?

Not really.

Doing this would lead us into a deadlock. Let's call the two requests Alice and Bob. First Alice makes a request
and it fails, she immediately tries to refresh the access token. She gets a new access token. During this Bob is
doing the same. And he refreshes the access token just before Alice retires her initial request. Now Alice will
fail again, and we're back to square one. This will loop until the heat death of the universe. Cheerful thought.

So let's say we fix that. We now make sure that only one of them make the request to refresh. We've got Charlene
handling the refreshes. Whenever one of them needs a refresh they'll ask Charlene. She's a smart actor so she'll
put up a little sign in the window saying "Back in a minute" when she's out refreshing tokens. This should
be enough right?

Not quite.

Because let's imagine that Alice makes a request and she goes to Charlene to get a refreshed access token.
While Alice and Charlene are working it out, Bob makes a request. But Bobs request takes a merry old time.
In fact it only returns a good time after Charlene has returned with the new access token. Now there's no sign up
in the window so he asks Charlene for a refresh. But this is a problem, because there is actually a new access token
but he doesn't know about it. Now let's imagine Alice is very fast and Bob is very slow, in this situation Alice
would have no problems, but Bob would constantly be sending Charlene out to get an access token, because
he arrives after the refresh of Alice, and Alice would have an invalid access token after his refresh. She would
then invalidate the access again, and Alice would get responses but Bob never would.

To solve this we need Charlene to be able to identify whether or not the access token Bob has is an old one,
and instead of using the refresh token she should just give him the latest access token she fetched. And we must
be done!

Nooot yet.

Because of the nature of this loop between them, let's imagine that all the access tokens that Charlene gets
are so short lived, and Alice and Bob so slow and lazy that they're always invalid by the time they try to use
them. This would put us in a different deadlock. Alice and Bob needs to know when to quit. There are two
pieces of information they need. 1. How long have I been working on my request? and 2. How many times have
I tried to refresh my access token? - given this they can decide to back off when enough is enough.

And that is then that. Thank you for your patience.
