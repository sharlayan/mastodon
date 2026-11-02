# Chat federation manual test

This checklist verifies native Mastodon chat against a CherryPick server. Run it before
shipping a change to chat ActivityPub handling.

## Setup

1. Start a local Mastodon with `CHERRYPICK_WEBFINGER_USE_HTTP=true` and chat enabled.
2. Start a CherryPick instance that can reach the Mastodon server.
3. Create `@alice` on Mastodon and `@bob` on CherryPick.
4. Make the two accounts discoverable and ensure neither blocks the other.

## Checklist

- [ ] Alice starts a 1:1 chat with Bob and sends text. Bob receives it.
- [ ] Bob replies and Alice receives it.
- [ ] Alice sends one image; Bob sees exactly one attachment.
- [ ] Bob edits a message; Alice sees the edited text and the edited label.
- [ ] Bob deletes a message; Alice sees the deleted-message placeholder.
- [ ] Alice reacts with a unicode emoji from the full picker; Bob sees the reaction.
- [ ] Alice removes the reaction; Bob sees it disappear.
- [ ] Alice creates a group, invites Bob, and Bob accepts.
- [ ] Both sides see each other in the member list with a remote badge.
- [ ] Alice adds a third remote member. Existing members receive the roster update.
- [ ] Alice renames the group; Bob sees the new title and description.
- [ ] Bob leaves the group; Alice sees the membership update.
- [ ] Alice deletes the group; Bob's mirror room disappears.
- [ ] Bob sends a 1:1 message while Alice's policy is `none`; no message appears and no error is shown to Bob.
- [ ] Bob invites Alice to a remote group while group invites are disabled; the invitation is rejected.
- [ ] Fetching `/chat/messages/:id` and `/chat/rooms/:id` with a signed request succeeds for members and returns 404 for non-members. Pending invitees may fetch the room metadata, but not messages or media.
- [ ] Fetching a deleted chat message returns an ActivityStreams `Tombstone`.

## Signed object check

```sh
curl -sS \
  -H 'Accept: application/activity+json' \
  -H "Signature: keyId=\"https://other.example/users/bob#main-key\",algorithm=\"rsa-sha256\",headers=\"(request-target) host date\",signature=\"...\"" \
  -H "Date: $(date -u +'%a, %d %b %Y %H:%M:%S GMT')" \
  https://mastodon.example/chat/messages/123
```

Use a real HTTP signature from the remote actor. An unsigned request must return `401`;
an unrelated signed actor must return `404`.
