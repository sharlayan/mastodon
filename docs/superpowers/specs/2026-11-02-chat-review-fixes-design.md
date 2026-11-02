# Chat review fixes

The user requested that all fifteen findings from the review of PR #2 be fixed and pushed to the existing `feat/chat-federation` branch. The reviewed revision is `e4812078a4`.

## Intent and constraints

Keep the existing native chat and CherryPick ActivityPub protocol. Correct authorization, media lifecycle, membership synchronization and UI state without redesigning the feature. Do not merge the PR or change unrelated functionality. Add behavioral regression tests, using the ten already reproduced backend failures as evidence.

## Approach

Use existing Rails services, serializers, account resolution and media access policies. Keep fixes near the source of each defect. Preserve signed object access and existing status-media behavior. For the UI, scope composer and async message state to the selected conversation and handle stream events consistently with the API contract.

A new protocol or wholesale frontend rewrite would broaden compatibility risk without being necessary for these fixes. These implementation choices are made by the assistant under the user's instruction to fix all findings.

## Required behavior

1. Only a room's verified owner may invite a local account. Existing room ownership and new remote room origin/attribution must be validated.
2. Chat attachments remain in use and survive orphan cleanup. Existing page, drive, draft and status attachment behavior remains intact.
3. Conversation switches must not carry edit targets, reply targets, uploads or draft text into another room.
4. Pending invitees receive room metadata but no messages before membership.
5. Valid incoming attachment-only messages are accepted atomically.
6. Remote chat media can be downloaded by authorized conversation members; adding support must not make private chat media publicly fetchable through the proxy.
7. Remote reaction stream payloads have the same account structure as local reactions.
8. Local group joins are announced to existing remote members.
9. Incoming roster Add resolves unknown accounts and canonical local actor URIs.
10. Pending invitees receive invitation cancellation; incoming Undo Invite cancels only authorized pending invitations.
11. Disabled chat or federation does not accept new incoming chat activities. Handling must consume recognized chat activities without falling through to public statuses.
12. A sender cannot tombstone another actor's future message. Bind pre-arrival tombstones to the authenticated actor and validate origin.
13. Live deletion removes attachment and reaction display as well as message content.
14. Incoming invitation events update the invitation list and count.
15. Responses and completions belonging to a previous conversation cannot replace the current room's messages or composer.

## Verification

Run focused red/green regressions, the changed chat/backend/media specs, frontend component tests and applicable lint/type checks. Resolve the test harness's worktree Git-path and absent Vite-manifest issues without modifying unrelated production code. Review the final implementation before committing/pushing remaining work. No external messages or PR comments are requested.
