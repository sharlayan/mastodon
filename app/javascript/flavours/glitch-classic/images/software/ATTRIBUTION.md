# Software icon sources

The SVG assets in this directory identify their respective software projects. Each
software icon is copied from that project's source repository. Only intrinsic width
and height on the root SVG were normalized to 128; internal artwork dimensions,
paths, and colors are unchanged. Pixelfed's source has no `viewBox`, so its original
50×50 coordinate system is declared as `viewBox="0 0 50 50"` to scale the artwork
with the normalized root size.

- Mastodon — this repository's upstream `app/javascript/images/logo-symbol-icon.svg`
  (`mastodon/mastodon`, AGPL-3.0).
- Misskey — `misskey-dev/misskey@159b1a44`,
  `packages/backend/assets/favicon.png` (128×128, SHA-256
  `4116e451d537265971251f2a07212c45ebeb239af64c259e34c19fd82b96034d`).
  The PNG bytes are embedded unchanged in an SVG container. Misskey's `COPYING`
  applies AGPL-3.0 to repository files unless otherwise stated; Misskey Hub also
  publishes its current brand assets under CC BY-SA.
- FoundKey — `FoundKeyGang/FoundKey@53c5130f`,
  `packages/backend/assets/favicon.png` (AGPL-3.0 repository; FoundKey separately
  credits its `logo.svg` to Blinry under CC BY 4.0, SHA-256
  `f1c60263532f05c1c905d1bae8b40f57935d6f5e888d62bf40f59e953f041437`).
  The PNG bytes are embedded unchanged in an SVG container.
- Catodon — `catodon/catodon@1bc5c0b4`,
  `packages/frontend/assets/favicon.png` (CC BY-SA 4.0 branding asset, SHA-256
  `3015d787fa09c36093c9858c91d46f52a4e4551cbd0e6479d5133f140a0ea537`).
  The PNG bytes are embedded unchanged in an SVG container.
- Sharkey — `TransFem-org/Sharkey@e60bbcd3`,
  `packages/backend/assets/favicon.png` (AGPL-3.0 repository, SHA-256
  `1bb58f07cfbd897a2bce525f5db40d18fffe77c48c52e4fc6897063db1e953c3`).
  The PNG bytes are embedded unchanged in an SVG container.
- Iceshrimp (Misskey fork) — `iceshrimp/iceshrimp@47dbb823`,
  `packages/backend/assets/favicon.png` (AGPL-3.0 repository, SHA-256
  `a3d6e5464d6ab6eb8a91d8228545b4d80a4b93df6c03a439f533326b4c5fc928`).
  The Git LFS PNG bytes are embedded unchanged in an SVG container.
  Both the `iceshrimp` and `iceshrimp.net` software identifiers use this icon.
- CherryPick — `kokonect-link/cherrypick@e7841484`,
  `packages/backend/assets/favicon.png` (AGPL-3.0 repository, SHA-256
  `96a73a02cf6c7072a1dd9ff33ceabdf844d9a3c36abe100d64fc804e5f761671`).
  The PNG bytes are embedded unchanged in an SVG container.
- Pleroma — `pleroma/pleroma@0a076443`, `priv/static/static/logo.svg`
  (`COPYING`: AGPL-3.0 for files without a separate exception).
- PeerTube — `Chocobozzz/PeerTube@fe0da961`,
  `client/src/assets/images/logo.svg` (AGPL-3.0 repository).
- Pixelfed — `pixelfed/pixelfed@c8bed78b`,
  `public/img/pixelfed-icon-color.svg` (AGPL-3.0 repository).
- Hollo — `fedify-dev/hollo@56f37f74`, `docs/public/favicon.svg`
  (AGPL-3.0 repository).
- Fedify — `fedify-dev/fedify@c2352c0e`, `logo.svg` (MIT repository).
- Hackers' Pub — `hackers-pub/hackerspub@346a7aa4`,
  `web/static/favicon.svg` (AGPL-3.0 repository).
- Fediverse fallback — `Fediverse logo proposal.svg` by Eukombos, CC0 1.0.

Firefish and Lemmy were excluded because a current official repository artwork source with clearly
compatible terms was not available in the repositories checked. Unlisted software
uses the CC0 Fediverse fallback.
