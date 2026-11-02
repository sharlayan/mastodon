# Chat Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all fifteen reviewed defects in PR #2 and push the current branch.

**Architecture:** Retain the existing chat API and ActivityPub format. Strengthen service authorization and media integration, then isolate frontend state by conversation and correct stream updates.

**Tech Stack:** Ruby 4.0.9, Rails 8.1, RSpec, React, TypeScript, Vitest, Yarn 4.

**Spec:** `docs/superpowers/specs/2026-11-02-chat-review-fixes-design.md`

## Global Constraints

- Work on `feat/chat-federation`; preserve unrelated files and do not merge.
- Keep the existing native chat and CherryPick ActivityPub protocol.
- Do not expose private chat media or message content to nonmembers.
- Add behavioral regression tests and record red/green evidence.
- Do not change unrelated production code to accommodate the local test environment.
- The user has explicitly authorized committing and pushing the completed fixes.

## Review Focus

- Forged invitations and cancellation for existing local rooms must be rejected.
- Deleted/hidden messages and former members must not accidentally grant media access.
- Disabled federation must consume recognized chat activities without status fallback.
- Unknown actors, local actor URIs and old tombstones must not break membership or message delivery.
- Delayed fetch/send/upload completions must not change another room's state.

### Task 1: Correct backend authorization, lifecycle and media integration

**Files:**

- Modify `app/services/sharlayan/chat_service.rb` and `app/lib/sharlayan/chat_federation/{incoming,payload}.rb` as needed.
- Modify ActivityPub activity dispatch for incoming cancellation and setting gates.
- Modify `app/serializers/rest/chat_conversation_serializer.rb`.
- Modify `app/models/concerns/sharlayan/media_attachment_extensions.rb`, `app/controllers/media_proxy_controller.rb`, `app/policies/media_attachment_policy.rb`, and minimal related model associations.
- Add/extend focused tests under `spec/services/sharlayan`, `spec/lib/activitypub/activity`, `spec/lib/sharlayan/chat_federation`, `spec/requests`, `spec/models`, and `spec/lib/vacuum` as appropriate.

**Interfaces:** Preserve existing public API signatures where possible. Outgoing `chat.reaction` must match `REST::ChatMessageReactionSerializer`. Frontend task consumes this unchanged local-reaction shape. Internal tombstone methods may accept actor identity; update existing callers/tests.

- [ ] Add regression coverage for spec requirements 1, 2, 4–12. The previous temporary `/tmp/chat_pr2_review_spec.rb` is a starting reference, not a required test structure. Add unknown-account Add and authorized/unauthorized Undo Invite tests, nonmember media denial, disabled incoming activity tests, and valid positive cases.
- [ ] Run new focused tests against unchanged implementation, verify expected failures, and record output.
- [ ] Enforce existing-room owner and remote-origin checks before creating invitations; prevent pending-invite message serialization.
- [ ] Include chat attachments in in-use/attached scopes and exclude them from orphan cleanup without losing existing page/draft/drive behavior. Authorize proxy downloads through current chat membership. Account for incoming attachments before content validation and retain atomicity.
- [ ] Emit consistent reaction payloads; deliver roster changes for local joins; resolve unknown/local actor URIs for Add; deliver cancellation directly to invitees and consume authenticated Undo Invite.
- [ ] Gate incoming chat writes using both settings, without ordinary status fallback, and bind pre-arrival tombstones to sender identity/origin.
- [ ] Run focused and related backend/media tests and RuboCop on changed Ruby files. Self-review and commit the task.

### Task 2: Correct frontend conversation state and stream handling

**Files:**

- Modify `app/javascript/flavours/glitch/features/chat/index.tsx`.
- Add component regressions in `app/javascript/flavours/glitch/features/chat/__tests__` and narrowly scoped helpers only if useful.

**Interfaces:** Consume existing message/invitation responses and the full account-bearing reaction event from Task 1. Preserve existing navigation and appearance. Use existing React/testing conventions.

- [ ] Add regression tests for changing A→home→B while editing or carrying draft/media/reply state; stale A responses after B; delayed send/upload completion after navigation; live deletion; incoming invitation refresh; and remote reaction rendering.
- [ ] Run tests before implementation and record expected failures. Exercise component behavior rather than grepping source or duplicating reducers in tests.
- [ ] Scope/reset composer and messages to conversation identity, discard outdated async responses and completions, and avoid changing another room's messages/composer.
- [ ] On delete, remove attachments and reactions from visible message state. On invitation events, refresh/update invitation state. Preserve safe reaction handling and deduplication.
- [ ] Run focused frontend tests and changed-file lint/type checks. Self-review and commit the task.

### Completion

- [ ] Review each task's diff against the spec and fix actionable findings.
- [ ] Run integrated backend/frontend checks, record any unrelated baseline limitations precisely, and obtain final code review.
- [ ] Verify clean worktree and commit history; push `feat/chat-federation` to origin and verify remote HEAD.
