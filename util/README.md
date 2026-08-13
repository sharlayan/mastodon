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

```sh
sudo util/source-install/install-debian.sh packages # Alpine은 install-alpine.sh
util/source-install/install-debian.sh check
sudo env BUILD_FROM_SOURCE=true \
  util/source-install/install-debian.sh build
sudo util/source-install/install-debian.sh database
sudo util/source-install/install-debian.sh configure
```

1GB 호스트에서 빌드하려면 swap이 최소 2GB 필요합니다.

컴파일러와 Bundler의 동시 작업 수는 의도적으로 1개로 제한하며,
가능하면 다른 호스트에서 빌드한 산출물을 사용하는 것을 권장합니다.

`configure`는 서비스를 설치하고 활성화하지만 자동으로 시작하지 않습니다.
PostgreSQL, Redis, `.env.production`을 초기화하고
`RAILS_ENV=production bundle exec rails db:prepare`를 실행한 다음
`mastodon-*` 서비스 3개를 시작합니다.

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
