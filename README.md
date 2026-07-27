# Mastodon Glitch - Sharlayan flavour

Mastodon 포크들에서 Emoji Reaction 을 지원하는 여러 버전을 참고하여 재구성한 버전입니다.
참고한 버전은 기능에 별도 표시를 해 두었습니다.

---

> [!WARNING]
> 본 포크 및 브랜치를 설치해 주고 수고비를 받는 등의 행위를 금합니다.

---

## 주요 커스텀 기능

아래는 `develop` 브랜치 기준의 간략한 목록입니다. 일부 기능은 관리자가 끄거나
사용 범위를 제한할 수 있습니다.

| 기능명                  | 설명                                                                                                                                                                                                  |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 리액션과 에모지         | 에모지 리액션, 반응한 게시물 모아보기, 민감 에모지와 계정·서버·에모지별 뮤트, 외부 클라이언트용 뮤트 처리를 지원합니다.                                                                               |
| MFM과 꾸미기            | 게시물 MFM 렌더링, 아바타 장식, 역할 배지 색상, 서버 테마 색상과 여러 glitch 스킨을 지원합니다.                                                                                                       |
| 게시와 컬렉션           | 서클, 클립, 안테나, 예약 게시, 서버 저장 초안, URL 자동 인용, 타임라인 인라인 작성과 조건에 맞는 장기 홈 피드 조회를 지원합니다.                                                                      |
| Pages와 Drive           | 공개 범위와 비밀번호를 설정할 수 있는 Pages, 여러 Page를 묶는 소책자, 계정별 파일·폴더를 관리하고 첨부에 다시 사용하는 Drive를 제공합니다.                                                            |
| Misskey 클라이언트 호환 | 별도로 활성화한 서버에서 Aria 등 일부 Misskey 클라이언트가 로그인, 타임라인, 게시, 리액션, 알림, Drive와 Pages의 지원 범위를 이용할 수 있습니다. Mastodon API와 ActivityPub 동작은 그대로 유지합니다. |
| 계정과 대화             | 여러 계정 연결·전환, 온라인 상태 표시, 채팅형 다이렉트 메시지, 에모지 스티커와 대화 알림 읽음 처리를 제공합니다.                                                                                      |
| 개인화된 glitch UI      | 내비게이션과 게시물 동작 버튼 순서, 작성 상자 구성, 콘텐츠 글자 크기·밀도, GIF 자동 재생, 서버 뱃지 등 여러 화면 설정을 브라우저와 선택적 서버 동기화로 관리할 수 있습니다.                           |
| 운영과 접근 제어        | 로컬 전용 발행·강제, 계정 및 게시물 접근 제한, 도메인 뮤트, 연합 제한 확장, 게시판형 공지, 역할별 추가 권한, 한국어 검색과 저사양 서버용 처리 옵션을 제공합니다.                                      |

> [!WARNING]
> 로컬 전용 발행 및 강제는 느슨한 커뮤니티 운영을 위한 기능입니다. 폐쇄형 자캐 커뮤니티에는
> 별도의 정책과 보호 기능이 포함된 `community` 모드를 사용해 주세요.

## 자캐 커뮤니티 (RP) 서버 모드

### 자캐 커뮤니티 모드

- 폐쇄형 자캐 커뮤니티 운영을 위해 연합을 차단하고 공개 접근 설정을 잠그는 서버 모드입니다.
- 설치 시 선택하거나 ENV 에서 설정을 변경할 수 있습니다.

> [!CAUTION]
> 이 기능은 .env 파일에서 `OC_ROLEPLAY_OPTION` 설정을 활성화 (`True`)해야만 동작합니다.
> 해당 기능을 켜면 해당 서버는 강제로 로컬 모드가 됩니다.

### 관리 타임라인

- 커뮤니티 내 사용자들의 모든 게시물을 확인하고 관리할 수 있는 기능입니다.
- 설치 시 선택하거나 ENV 에서 설정을 변경할 수 있습니다.

> [!CAUTION]
> 이 기능은 .env 파일에서 `OC_ROLEPLAY_OPTION` 설정을 활성화 (`True`)해야만 동작합니다.
> 절대 이 기능을 실제 연합 중인 서버에서 사용하지 마십시오. 운영의 신뢰성을 깨트릴 수 있습니다.
> 활성화 시 개인 멘션 선택 시 경고 메시지에 안내 문구가 출력됩니다.

---

일부 기능은 아래 저장소/인스턴스의 기능을 참조했습니다.

`F-Finene`, `Urusai`, `KmyBlue`, `Qdon`

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
