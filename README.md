# Mastodon Glitch - Custodon flavour

Mastodon 포크들에서 Emoji Reaction 을 지원하는 여러 버전을 참고하여 재구성한 버전입니다.
참고한 버전은 기능에 별도 표시를 해 두었습니다.

---

> [!WARNING]
> 본 포크 및 브랜치를 설치해 주고 수고비를 받는 등의 행위를 금합니다.

---

이 포크가 포함하는 커스텀 기능은 대략적으로 아래와 같습니다.

### \* 에모지 리액션

Ref: Urusai! (neatchee), F-Finene

Misskey 및 Pleroma/Akkoma 와 호환되는 에모지 리액션을 사용할 수 있습니다. 에모지 리액션에 별도의 민감함 설정 및 라이센스 표시, 유저별 뮤트 기능을 포함합니다. 기능 자체를 비활성화 할 수 있습니다.

그 외 게시물별 수신 제어, 스트리밍 전달 최적화, 웹 알림 인라인 렌더 등을 지원합니다.

### \* 계정 및 커뮤니케이션

Ref: misskey-dev, misskey.bscone, sharlayan(legacy)

서버 내 계정 전환 기능은 보안을 위해 Misskey의 계정 전환 방식을 서버에 이관한 형태로 계정 전환 기능을 포함하며 계정에 인증 정보를 종속시키는 방식으로 서버에 권한을 보관합니다. 또한 블루스카이 브릿지 게시물 전달 시 조용한 공개 게시물도 블루스카이 브릿지로 전송할 수 있도록 합니다.

연결한 계정의 알림을 메인 계정으로 수신할 수 있습니다. 앱 알림 허용 시 메인 계정 로그인 만으로 알림을 모두 받아볼 수 있습니다.

Misskey 의 팔로우 자동 수락 (내가 팔로우하는 상대의 승인) 기능을 포함합니다.
팔로워 목록에서 Bio및 Misskey 스타일 팔로워 수락 메시지 등을 확인할 수 있습니다.

### \* Misskey 호환 레이어

Ref: misskey-dev

Misskey 호환 앱에서 커스텀 기능을 대부분 이용할 수 있도록 조정되어 있습니다. 옵션을 켜면 Flare 에서 Misskey 호환 서버로 인식하며 Aria for Misskey 등의 MiAuth 기능을 이용한 로그인을 지원합니다. 보안 정책상 PsKey 는 사용에 문제가 있을 수 있습니다.

페이지 (자체 커스텀) 및 드라이브, 아바타 장식 및 장식 연합, Misskey 계정으로부터 계정 이관 강화 등의 기능을 포함합니다.

### \* 확장 기능

Ref: kmyblue, Qdon, misskey-dev

안테나, 서클, 예약 게시 웹 인터페이스, 서버 초안(게시글 임시 저장) 클립, 게시판 공지사항(Misskey-like notification) 등의 기능을 포함합니다.

MfM렌더링을 지원합니다.

각 기능은 원하지 않는 경우 활성화하지 않을 수 있습니다. 기본적으로 비활성화 되어 있습니다.

### \* 타임라인 제어 및 연합 정책

Ref: sharlayan(legacy), kmyblue, Qdon

서버측 기능으로 릴레이 비표시, 릴레이 무시, 유행 등록 안함, 좋아요 거부 등을 제어할 수 있습니다. 또한 유저가 도메인 뮤트, 에모지 표시 안함/무시 등 가시성 제한이 가능합니다.

연합 소프트웨어 확인 및 식별 (커스텀+Kmyblue), 서버 배지 표시 기능 등이 연합 정책에 포함됩니다.

### \* 인터페이스

Ref: F-Finene, Polyamspace, BirdSiteUI

게시글 접기 (Polyamspace, old glitch-soc) 및 읽지 않은 알림 게시글 접지 않음 (Polyamspace), DM(개인 멘션) 전용 인터페이스 지원으로 읽음 시 자동 알림 삭제 (멘션, 리액션)로 미확인 멘션 구분 강화 (afb53d1). 그려보세요 glitch-soc 기능 강화 (doodle), 덱 컬럼 조정 기능, local-setting 확장 등을 포함하고 있습니다.

커스텀 BirdSiteUI를 기본 포함하고 있습니다.

### \* 관리 및 테마 기능 강화

세부 브랜딩 등 기존 소스 제어로만 편집할 수 있는 영역을 사용자와 서버 양쪽으로 커스텀할 수 있도록 강화. css 세부 조정 등을 통해 상세 제어가 가능하며 별다른 지식 없이도 인터페이스 커스텀 가능. 서버 브랜딩 색상 설정 가능. OpenSearch 구분 기능, 한글 검색 기능 강화 \*(Ref: Qdon), OpenSearch 컨테이너 포함 등 관리용 기능 포함.

API 제한을 우회할 수 있는 권한을 별도로 지정할 수 있어 서버 내 봇 운영 등에 도움을 줄 수 있습니다. 다만 연합에 과도한 요청을 보내지 않도록 주의가 필요합니다.

작성 가능 글자수를 서버 수정 없이 변경할 수 있도록 조정할 수 있습니다.

### \* 자작캐릭터 커뮤니티 모드

main/develop 브랜치에는 가볍게 제한하는 기능만 있으며 관리용 타임라인 등은 포함하고 있지 않으므로 필요 시 community 브랜치를 사용해 주시기 바랍니다.

강제 로컬 모드, 글리치 테마 강제, 아바타 장식 강제, 초대 권한 제어 (설치 시에 커뮤니티로 설치해야 적용되므로 일반 설치 시 직접 권한 회수 권장), 연합/로컬 타임라인 비활성화 (완전 접근 제한. 호환 앱에서도 열람 불가) 기능을 포함합니다.

> [!CAUTION]
> community 브랜치에서는 유저 신뢰성을 파괴할 수 있는 관리 타임라인 기능이 존재합니다.
>
> 로컬 전용으로 발행된 사용자간 대화에서만 적용되므로 문제는 크게 되지 않지만 사용자에게 고지가 필요합니다.

아래 두 기능은 community 에서만 사용 가능한 기능입니다.

#### 관리 타임라인

로컬 전용으로 발행한 유저의 DM및 게시물 가시성 제한 없이 열람 가능.

다만 관리 권한만으로는 운영(Owner)와 유저 간의 DM을 열람할 순 없습니다. Owner 일 경우 로컬 발행된 모든 게시물에 대한 접근 권한을 가집니다.

#### 게시글 소프트 삭제

일시적으로 유저가 편파를 위해 개인 메시지로 외부 SNS계정을 전달하고 삭제하는 등 (상식적으로 일어나서는 안 되지만) 의 운영 감시 회피를 막아주는 기능입니다. 삭제된 게시글을 Owner가 관리 타임라인에서 열람할 수 있습니다. 필요 시 Owner는 해당 게시물을 하드 삭제할 수 있습니다.

### \* 그 외

커스텀 편의성을 위한 별도 설정 탭 등의 관리 편의성 강화, 유저 인터페이스 편집 등의 QoL 기능을 포함하고 있습니다.

여기에 적혀있지 않은 다수의 사소한 변경점들이 존재합니다.

> [!WARNING]
> 이 Fork 는 1인 개발/관리이므로 사용 시 신중하게 선택해 주시기 바랍니다. 한번 전환한 이후 커스텀 기능에서 작성된 모든 기능은 다른 Fork로 전환 시 접근하지 못하는 일종의 도달 불가 정보가 될 수 있습니다.

---

This project is not affiliated with or endorsed by Mastodon GmbH or Mastodon Inc.

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
