# Mastodon Glitch - Sharlayan flavour

Mastodon 포크들에서 Emoji Reaction 을 지원하는 여러 버전을 참고하여 재구성한 버전입니다.
참고한 버전은 기능에 별도 표시를 해 두었습니다.

---

> [!WARNING]
> 본 포크 및 브랜치를 설치해 주고 수고비를 받는 등의 행위를 금합니다.

---

## 커스텀 된 기능 목록

### 테마 색상 지정

- 웹앱 설치 시 표시되는 색상 및 misskey 계열 소프트웨어에서 서버 정보 표시 시 사용되는 색상을 파일 수정 없이 커스텀 할 수 있습니다.

### 에모지 리액션

- misskey 및 AP소프트웨어군에서 지원하는 에모지 리액션을 사용할 수 있습니다.

  서버에서 사용 여부를 관리하며 `관리 - 서버 설정 - 외관` 에서 끄고 켤 수 있습니다.

- 반응을 남긴 게시물을 모아보거나 자동 툿 삭제 기능에서 예외로 지정할 수 있습니다.

- 에모지 리액션의 경우 [Urusai!](https://github.com/neatchee/mastodon) glitch 구현 등의 포크 기능을 참조했습니다.

- 미스키 스타일 에모지 리액션 목록 툴팁 및 자동 툿 삭제 예외는 [mstdn.lalafell.org F-Finene](https://github.com/F-Finene/mastodon) 에서 포팅한 기능입니다. 일부 리액션 형식도 해당 포크에 맞추어 조정했습니다.

### MFM (Markup language For Misskey)

- misskey 에서 사용하는 markup language 를 지원합니다. 현재는 게시글에만 렌더됩니다.

  서버에서 사용 여부를 관리하며 `관리 - 서버 설정 - 외관` 에서 끄고 켤 수 있습니다.

- 기본은 `사용 안 함` 이며 서버에서 사용 설정을 하더라도 유저별 설정이 가능합니다.

### 아바타 장식

- misskey 및 포크 소프트웨어에서 사용하는 아바타 장식을 연합하거나, 사용할 수 있습니다.
- 서버에서 사용 여부를 관리하며 `관리 - 서버 설정 - 외관` 에서 끄고 켤 수 있습니다.

### 로컬 전용 발행 및 접근 제어

- 로컬 전용 발행 (Glitch) 기능 및

  로컬 전용 강제, 계정 정보 보기 및 개별 게시물 접근 설정이 가능하며 이 설정은

  `관리 - 서버 설정 - 발견하기` 에서 편집할 수 있습니다.

### 관리 타임라인

- 원활한 자캐 커뮤 운영을 위한 공개범위 제약 없는 관리용 타임라인 및 열람 바이패스 기능

> [!CAUTION]
> 이 기능은 .env 파일에서 `OC_ROLEPLAY_OPTION` 설정을 활성화 (`True`)해야만 동작합니다.
> 해당 기능을 켜면 해당 서버는 강제로 로컬 모드가 됩니다.
> 절대 이 기능을 실제 연합 중인 서버에서 사용하지 마십시오. 운영의 신뢰성을 깨트릴 수 있습니다.
> 활성화 시 개인 멘션 선택 시 경고 메시지에 안내 문구가 출력됩니다.

### 연합 제한 및 차단 기능 강화

- 연합 제한 기능에 `좋아요 및 에모지 리액션 거부`, `릴레이를 통한 수신 거부`, `유행에서 제외`가 추가되어 있습니다.

- 이 기능의 경우 [kmyblue](https://github.com/kmycode/mastodon) 포크의 기능을 포팅했습니다.

### 로컬 전용 게시판형 공지사항

- 기존 공지사항은 기간이 지나면 열어볼 수 없고 긴 내용을 적기 불편하다는 단점을 보완하기 위해 추가한 기능입니다.

  자캐 커뮤니티 등에서 공지 계정을 따로 마련하지 않아도 되어 유용하게 사용할 수 있습니다.

### API 제한 우회 역할

- 서버 제공 봇 등 API 제한을 초과할 가능성이 있는 사용자를 위해 별도의 역할로 우회할 수 있습니다.

  역할에서 해당 옵션을 지정하면 해당 역할에 포함된 계정은 별도의 API 제한을 받지 않습니다.

- 자캐 커뮤니티 등에서 콘텐츠 봇 등을 운영할 때 유용하게 사용할 수 있습니다.

  봇을 연합우주 소속에서 사용하는 경우 공개 게시물로 작성하지 않는 것을 강력히 권장합니다.

### 연합 인스턴스 정보 뱃지

- misskey 풍의 서버 정보 뱃지를 제공합니다. 유저별 설정으로 동작합니다.

### 서클 및 클립

- 게시물을 받을 대상을 제한하는 기능인 X (구 트위터)의 기능 `서클` 과

  misskey 소프트웨어 계열에서 사용하는 게시물 집합 기능인 `클립` 기능을 제공합니다.

- 서버에서 사용 여부를 관리하며 `관리 - 서버 설정 - 기타` 에서 끄고 켤 수 있습니다.

- 서클 기능의 경우 [kmyblue](https://github.com/kmycode/mastodon) 포크의 기능을 포팅했습니다.

### 기타 UI

- 개인 멘션(DM) 인터페이스를 몰입형 채팅 형식(X, 구 트위터)으로 변경

- 에모지 피커 lazyload 및 카테고리 선택 개선

- 그 외 사소한 유저 경험 개선

---

아래부터는 Glitch SoC 의 원본 Readme 입니다.

# Mastodon Glitch

[![Ruby Testing](https://github.com/glitch-soc/mastodon/actions/workflows/test-ruby.yml/badge.svg)](https://github.com/glitch-soc/mastodon/actions/workflows/test-ruby.yml)
[![Crowdin](https://badges.crowdin.net/glitch-soc/localized.svg)][glitch-crowdin]

[glitch-crowdin]: https://crowdin.com/project/glitch-soc

So here's the deal: we all work on this code, and anyone who uses that does so absolutely at their own risk. can you dig it?

- You can view documentation for this project at [glitch-soc.github.io/docs/](https://glitch-soc.github.io/docs/).
- And contributing guidelines are available [here](CONTRIBUTING.md) and [here](https://glitch-soc.github.io/docs/contributing/).

Mastodon Glitch Edition is a fork of [Mastodon](https://github.com/mastodon/mastodon). Upstream's README file is reproduced below.

---

> [!NOTE]
> Want to learn more about Mastodon?
> Click below to find out more in a video.

<p align="center">
  <a style="text-decoration:none" href="https://www.youtube.com/watch?v=IPSbNdBmWKE">
    <img alt="Mastodon hero image" src="./docs/hero-nodes.gif" />
  </a>
</p>

<p align="center">
  <a style="text-decoration:none" href="https://github.com/mastodon/mastodon/releases">
    <img src="https://img.shields.io/github/release/mastodon/mastodon.svg" alt="Release" /></a>
  <a style="text-decoration:none" href="https://github.com/mastodon/mastodon/actions/workflows/test-ruby.yml">
    <img src="https://github.com/mastodon/mastodon/actions/workflows/test-ruby.yml/badge.svg" alt="Ruby Testing" /></a>
  <a style="text-decoration:none" href="https://crowdin.com/project/mastodon">
    <img src="https://d322cqt584bo4o.cloudfront.net/mastodon/localized.svg" alt="Crowdin" /></a>
</p>

Mastodon is a **free, open-source social network server** based on [ActivityPub](https://www.w3.org/TR/activitypub/) where users can follow friends and discover new ones. On Mastodon, users can publish anything they want: links, pictures, text, and video. All Mastodon servers are interoperable as a federated network (users on one server can seamlessly communicate with users from another one, including non-Mastodon software that implements ActivityPub!)

## Navigation

- [Project homepage 🐘](https://joinmastodon.org)
- [Donate to support development 🎁](https://joinmastodon.org/sponsors#donate)
  - [View sponsors](https://joinmastodon.org/sponsors)
- [Blog 📰](https://blog.joinmastodon.org)
- [Documentation 📚](https://docs.joinmastodon.org)
- [Official container image 🚢](https://github.com/mastodon/mastodon/pkgs/container/mastodon)

## Features

<img src="./app/javascript/images/elephant_ui_working.svg?raw=true" align="right" width="30%" />

**Part of the Fediverse. Based on open standards, with no vendor lock-in.** - the network goes beyond just Mastodon; anything that implements ActivityPub is part of a broader social network known as [the Fediverse](https://jointhefediverse.net/). You can follow and interact with users on other servers (including those running different software), and they can follow you back.

**Real-time, chronological timeline updates** - updates of people you're following appear in real-time in the UI.

**Media attachments** - upload and view images and videos attached to the updates. Videos with no audio track are treated like animated GIFs; normal videos loop continuously.

**Safety and moderation tools** - Mastodon includes private posts, locked accounts, phrase filtering, muting, blocking, and many other features, along with a reporting and moderation system.

**OAuth2 and a straightforward REST API** - Mastodon acts as an OAuth2 provider, and third party apps can use the REST and Streaming APIs. This results in a [rich app ecosystem](https://joinmastodon.org/apps) with a variety of choices!

## Deployment

### Tech stack

- [Ruby on Rails](https://github.com/rails/rails) powers the REST API and other web pages.
- [PostgreSQL](https://www.postgresql.org/) is the main database.
- [Redis](https://redis.io/) and [Sidekiq](https://sidekiq.org/) are used for caching and queueing.
- [Node.js](https://nodejs.org/) powers the streaming API.
- [React.js](https://reactjs.org/) and [Redux](https://redux.js.org/) are used for the dynamic parts of the interface.
- [BrowserStack](https://www.browserstack.com/) supports testing on real devices and browsers. (This project is tested with BrowserStack)
- [Chromatic](https://www.chromatic.com/) provides visual regression testing. (This project is tested with Chromatic)

### Requirements

- **Ruby** 3.3+
- **PostgreSQL** 14+
- **Redis** 7.0+
- **Node.js** 22+
- **FFmpeg** 5.1+

This repository includes deployment configurations for **Docker and docker-compose**, as well as for other environments like Heroku and Scalingo. For Helm charts, reference the [mastodon/chart repository](https://github.com/mastodon/chart). A [**standalone** installation guide](https://docs.joinmastodon.org/admin/install/) is available in the main documentation.

## Contributing

Mastodon is **free, open-source software** licensed under **AGPLv3**. We welcome contributions and help from anyone who wants to improve the project.

You should read the overall [CONTRIBUTING](https://github.com/mastodon/.github/blob/main/CONTRIBUTING.md) guide, which covers our development processes.

You should also read and understand the [CODE OF CONDUCT](https://github.com/mastodon/.github/blob/main/CODE_OF_CONDUCT.md) that enables us to maintain a welcoming and inclusive community. Collaboration begins with mutual respect and understanding.

You can learn about setting up a development environment in the [DEVELOPMENT](docs/DEVELOPMENT.md) documentation.

If you would like to help with translations 🌐 you can do so on [Crowdin](https://crowdin.com/project/mastodon).

## LICENSE

Copyright (c) 2016-2026 Eugen Rochko (+ [`mastodon authors`](AUTHORS.md))

Licensed under GNU Affero General Public License as stated in the [LICENSE](LICENSE):

```text
Copyright (c) 2016-2026 Eugen Rochko & other Mastodon contributors

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU Affero General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option) any
later version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
details.

You should have received a copy of the GNU Affero General Public License along
with this program. If not, see https://www.gnu.org/licenses/
```
