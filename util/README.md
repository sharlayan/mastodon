# 유틸리티

## 1 CPU / 1GB 소스 설치

> [!WARNING]
>
> 1 CPU / 1GB 환경을 권장하지는 않습니다. 다만 1 ~ 2명의 극소규모 인스턴스인 경우 불안정 할 수 있지만 동작을 보장합니다.
> 이 환경의 경우 docker 보다 소스 실행이 메모리 사용에 더 여유롭습니다.

`source-install/`에는 기존 개발용 `build.sh`와 분리된 소스 배포 도우미가 들어 있습니다.

- `1cpu-1gb.env`: Puma 단일 프로세스, 스레드 1~2개, Sidekiq 동시 실행 수 1 설정
- `configure-1cpu-1gb.sh`: 빌드 산출물을 검증하고 systemd 또는 OpenRC 서비스 설치
- `install-debian.sh`: Debian 계열 패키지 설치 및 빌드 도우미
- `install-alpine.sh`: Alpine 패키지 설치 및 빌드 도우미

설치 도우미는 검증되지 않은 외부 설치 프로그램으로 Ruby 또는 Node.js를 내려받지 않습니다.
먼저 `.ruby-version`과 `.nvmrc`에 고정된 버전을 설치한 다음 아래 명령을 사용합니다.
Node.js는 `package.json`의 `engines.node` 이상이어야 하며, 빌드에는 Corepack으로 활성화한 Yarn 4가 필요합니다.
Node.js 25부터는 Corepack이 포함되지 않으므로 `npm install -g corepack`을 먼저 실행하고, Node.js 24에서는
`corepack enable`을 실행합니다.

```sh
sudo util/source-install/install-debian.sh packages # Alpine은 install-alpine.sh
util/source-install/install-debian.sh check
sudo env BUILD_FROM_SOURCE=true \
  util/source-install/install-debian.sh build
sudo -u mastodon cp .env.production.sample .env.production # 값을 채운 뒤 진행
sudo util/source-install/install-debian.sh database
sudo util/source-install/install-debian.sh configure
```

`configure`는 `.env.production`이 없으면 실패하므로, 그 전에 `.env.production`을 만들고
데이터베이스·Redis·도메인·비밀 키 값을 채워야 합니다.

1GB 호스트에서 빌드하려면 swap이 최소 2GB 필요합니다.

컴파일러와 Bundler의 동시 작업 수는 의도적으로 1개로 제한하며,
가능하면 다른 호스트에서 빌드한 산출물을 사용하는 것을 권장합니다.

`configure`는 서비스를 설치하고 활성화하지만 자동으로 시작하지 않습니다.
PostgreSQL 데이터베이스와 Redis가 준비되었는지 확인하고
`RAILS_ENV=production bundle exec rails db:prepare`를 실행한 다음
`mastodon-*` 서비스 3개를 시작하고 `sudo util/source-install/configure-1cpu-1gb.sh verify`로 확인합니다.

Custodon 나이틀리 및 수동 이미지 빌드 워크플로는
`mastodon-assets-<commit>.tar.gz`도 게시합니다. 소스 checkout 루트에서 압축을 풀면 1GB
호스트에서 직접 컴파일하지 않고 해당 commit과 일치하는 `public/packs`와 `public/assets`를
설치할 수 있습니다.

```sh
sha256sum -c mastodon-assets-<commit>.tar.gz.sha256
tar -xzf mastodon-assets-<commit>.tar.gz
```

명시적인 `database` 단계는 1GB 전용 호스트에 PostgreSQL 프로필을 적용합니다. shared
buffers 64MB, 연결 30개, work memory 2MB, autovacuum worker 2개, 제한된
maintenance/WAL 메모리를 사용하고 PostgreSQL JIT를 비활성화 합니다. 기본적으로 PostgreSQL을
재시작하며 별도의 유지보수 재시작을 계획한 경우에만 `RESTART_DATABASE=false`를 사용하고,
재시작 후 다음 명령으로 검증하시기 바랍니다.

```sh
sudo util/source-install/configure-1cpu-1gb.sh database-check
```

## 음성 통화 시그널 서비스 (`voice-signal.sh`)

Chat 음성 통화에서 브라우저의 LiveKit 시그널링 연결을 외부 음성 릴레이로 중계하는 .NET 10
서비스(`voice_signal/`)를 빌드하고, 실행 방식을 등록·점검합니다.
`source-install/` 도우미와 같이 POSIX `sh`(Debian dash, Alpine BusyBox ash)로 실행되며 bash가 필요하지 않습니다.

### 실행 방식

| 구분      | `VOICE_SIGNAL_RUN` | 실행 주체                           | 실행 대상                                            |
| --------- | ------------------ | ----------------------------------- | ---------------------------------------------------- |
| 직접 실행 | `service-binary`   | 전용 서비스 `mastodon-voice-signal` | `voice_signal/publish/VoiceSignal`                   |
| 직접 실행 | `service-docker`   | 전용 서비스 `mastodon-voice-signal` | 컨테이너 이미지                                      |
| 실행 위탁 | `puma-auto`        | `mastodon-web`의 Puma 마스터        | 로컬 빌드가 있으면 실행 파일, 없으면 컨테이너 이미지 |
| 실행 위탁 | `puma-binary`      | `mastodon-web`의 Puma 마스터        | `voice_signal/publish/VoiceSignal`                   |
| 실행 위탁 | `puma-docker`      | `mastodon-web`의 Puma 마스터        | 컨테이너 이미지                                      |

- 직접 실행은 systemd 또는 OpenRC가 재시작을 맡습니다. 웹 서비스를 재시작해도 통화 시그널 연결이
  끊기지 않습니다.
- 실행 위탁은 서비스를 따로 등록하지 않습니다. Puma가 시작·재시작·종료를 함께 관리하고, 프로세스가 죽으면
  1초부터 최대 60초 간격으로 다시 띄웁니다. Puma가 비정상 종료되면 표준 입력이 닫힌 것을 감지해 스스로
  종료합니다.
- 두 방식을 함께 쓰면 같은 포트를 두고 충돌합니다. `apply`는 다른 방식의 설정을 지우고,
  `bin/voice-signal run`은 `VOICE_SIGNAL_SPAWN`이 설정되어 있으면 실행을 거부합니다.
- Docker Compose로 운영한다면 이 스크립트 대신 `ghcr.io/<owner>/mastodon-voice-signal` 이미지를 별도
  서비스로 둡니다.

### 빌드

로컬 실행 파일(self-contained 단일 파일, 약 100 MB)을 만듭니다.

```sh
util/voice-signal.sh build                    # root로 실행하면 앱 사용자로 바꿔 실행
RAILS_ENV=production bin/voice-signal build   # 결과: voice_signal/publish/VoiceSignal
```

- `dotnet`(.NET 10 SDK)이 있으면 그것으로, 없으면 `mcr.microsoft.com/dotnet/sdk:10.0` 컨테이너로
  빌드합니다.
- 호스트 CPU에 맞춰 `linux-x64`·`linux-arm64`(Alpine은 `linux-musl-*`)로 빌드합니다.
- 코드를 갱신하면 다시 빌드해야 합니다. `voice_signal/publish/`는 git에서 제외됩니다.
- `voice_signal/publish.new/`에 빌드한 뒤 성공했을 때만 기존 실행 파일과 바꾸므로, 빌드가 실패해도 실행 중인
  서비스의 실행 파일은 그대로 남습니다.

컨테이너 이미지는 Microsoft 공식 이미지(`sdk:10.0`에서 빌드, `aspnet:10.0`에서 실행)를 기반으로 합니다.

```sh
util/voice-signal.sh pull-image    # VOICE_SIGNAL_IMAGE(기본 ghcr.io/sharlayan/mastodon-voice-signal:edge) 받기
util/voice-signal.sh build-image   # LOCAL_IMAGE(기본 mastodon-voice-signal:local)로 로컬 빌드
```

로컬 이미지를 쓰려면 `.env.production`에 `VOICE_SIGNAL_IMAGE=mastodon-voice-signal:local`과
`VOICE_SIGNAL_IMAGE_PULL=never`를 지정합니다.

### 실행

```sh
RAILS_ENV=production bin/voice-signal command --mode binary   # 실행할 명령 확인 (시크릿 값은 출력하지 않음)
RAILS_ENV=production bin/voice-signal run --mode docker       # 포그라운드 실행
```

`bin/voice-signal`은 Rails와 같은 순서(`.env.production.local`, `.env.local`, `.env.production`, `.env`)로
환경 파일을 읽고 프로세스 환경 변수를 우선합니다. `--mode`는 `auto`(기본), `binary`, `docker` 중 하나입니다.

실행 위탁은 `.env.production`에 `VOICE_SIGNAL_SPAWN=auto|binary|docker`를 지정하고 웹 서비스를
재시작하면 됩니다. `apply`는 이 값과 아래 systemd 설정을 함께 맞춥니다.

### 서비스 등록 확인

```sh
util/voice-signal.sh check    # 읽기 전용, 문제가 있으면 종료 코드 1
util/voice-signal.sh verify   # 상태 확인 응답을 최대 30초 기다림
```

`check`는 다음을 확인합니다.

- `bin/voice-signal`, 환경 파일, `SECRET_KEY_BASE`, `LOCAL_DOMAIN`/`WEB_DOMAIN`
- `VOICE_SIGNAL_URL`이 `VOICE_SIGNAL_PATH`로 끝나는지
- 현재 실행 방식(위탁 설정값, 전용 서비스의 등록·부팅 활성·실행 상태)과 두 방식의 중복
- 실행 대상의 준비 상태: 로컬 빌드, docker 설치와 앱 사용자의 docker 그룹, 이미지 존재 여부
- 위탁 시 `mastodon-web` 서비스가 .NET 런타임에 필요한 `memfd_create`를 막는지, `PrivateUsers=true`인지
- `http://127.0.0.1:<VOICE_SIGNAL_PORT><VOICE_SIGNAL_PATH>/health` 응답
- nginx 설정에 `location <VOICE_SIGNAL_PATH>`가 있는지

### 서비스 등록

```sh
sudo VOICE_SIGNAL_RUN=service-binary util/voice-signal.sh apply
sudo VOICE_SIGNAL_RUN=puma-auto util/voice-signal.sh apply
sudo util/voice-signal.sh remove
```

`apply`는 다음을 변경합니다.

| 방식        | systemd                                                                               | OpenRC                                                            |
| ----------- | ------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| `service-*` | `/etc/systemd/system/mastodon-voice-signal.service` 작성·활성화, 웹 drop-in 삭제      | `/etc/init.d/mastodon-voice-signal` 작성, `default` runlevel 추가 |
| `puma-*`    | 전용 서비스 삭제, `/etc/systemd/system/mastodon-web.service.d/voice-signal.conf` 작성 | 전용 서비스 삭제                                                  |

- 두 경우 모두 `.env.production`의 `VOICE_SIGNAL_SPAWN`을 맞추고(`service-*`는 제거) 웹 서비스를
  재시작합니다. 환경 파일은 바꾸기 전에 `.env.production.voice-signal-<시각>.bak`으로 백업합니다.
- systemd 전용 서비스(`binary`)에는 `ProtectSystem=strict`, `ProtectHome=read-only`,
  `SystemCallFilter=@system-service` 등의 제한을 겁니다. `docker`는 `SupplementaryGroups=docker`로
  docker 소켓에 접근합니다. OpenRC 로그는 `log/voice-signal.log`에 남습니다.
- 웹 drop-in은 `SystemCallFilter=memfd_create`를 추가합니다. Mastodon 기본 `mastodon-web.service`의
  시스템 콜 필터가 `@ipc`를 막아 .NET 런타임이 시작하자마자 종료되기 때문입니다. 컨테이너를 쓸 수 있는
  방식이고 docker 그룹이 있으면 `PrivateUsers=false`, `SupplementaryGroups=docker`도 추가합니다.
- `RESTART_WEB=false`는 웹 재시작을, `START_SERVICE=false`는 전용 서비스 시작을 생략합니다.
- `DRY_RUN=true SYSTEMD_DIR=/tmp/systemd OPENRC_DIR=/tmp/init.d`로 실행하면 root 없이 서비스 파일만 그
  디렉터리에 쓰고, 환경 파일과 서비스 관리자 변경은 출력만 합니다. `INIT_SYSTEM=systemd|openrc`로
  감지 결과를 바꿀 수 있습니다.
- `APP_DIR`, `APP_USER`, `ENV_SOURCE`, `BUNDLE_BIN`, `SERVICE`, `WEB_SERVICE`를 덮어쓸 수 있습니다.

### 웹 서버

브라우저는 `wss://<WEB_DOMAIN>/voice-signal`로 접속하므로, 웹 서버가 이 경로를 서비스로 넘겨야 합니다.
`dist/nginx.conf`에는 이 경로(`upstream voice_signal`, `location ^~ /voice-signal/`)가 들어 있습니다. 기존 설정을 쓰는 경우 아래 블록을 추가합니다. 다른 서버 멤버에게 통화를 제공하면(관리 설정 "다른 서버 멤버에게 통화 제공") 그 참가자들은 `/livekit/rtc`로 접속하므로, 같은 블록을 `location ^~ /livekit/rtc`로 하나 더 둡니다. `/livekit/federation/`은 Mastodon(웹)이 처리하므로 넘기지 않습니다.

```nginx
location /voice-signal/ {
  proxy_pass http://127.0.0.1:4100;
  proxy_http_version 1.1;
  proxy_set_header Host $host;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
  proxy_set_header Upgrade $http_upgrade;
  proxy_set_header Connection $connection_upgrade;
  proxy_buffering off;
  proxy_read_timeout 1h;
}
```

나머지 설정 변수(`VOICE_SIGNAL_PORT`, `VOICE_SIGNAL_TRUSTED_PROXIES` 등)는 `.env.production.sample`의
음성 통화 항목을 참고합니다.
