#!/bin/sh
set -eu

PROGRAM=${0##*/}
MODE=${1:-check}
APP_USER=${APP_USER:-mastodon}
APP_GROUP=${APP_GROUP:-mastodon}
APP_DIR=${APP_DIR:-/home/mastodon/live}
MIN_SWAP_MIB=${MIN_SWAP_MIB:-1900}
BUILD_FROM_SOURCE=${BUILD_FROM_SOURCE:-false}

fail() {
  printf '[%s] ERROR: %s\n' "$PROGRAM" "$*" >&2
  exit 1
}

require_alpine() {
  [ -f /etc/alpine-release ] || fail 'this helper supports Alpine Linux only'
}

check_swap() {
  swap_mib=$(awk '/^SwapTotal:/ { print int($2 / 1024) }' /proc/meminfo)
  [ "$swap_mib" -ge "$MIN_SWAP_MIB" ] ||
    fail "at least ${MIN_SWAP_MIB} MiB swap is required for a 1 GiB source build (found ${swap_mib} MiB)"
}

install_packages() {
  [ "$(id -u)" -eq 0 ] || fail 'packages must run as root'
  apk add --no-cache \
    build-base ca-certificates curl ffmpeg git icu-dev imagemagick jemalloc \
    libffi-dev libidn-dev libpq-dev openssl-dev libxml2-dev libxslt-dev \
    libyaml-dev linux-headers nodejs npm postgresql postgresql-contrib \
    redis ruby ruby-bundler ruby-dev rust cargo vips-dev zlib-dev
  getent group "$APP_GROUP" >/dev/null 2>&1 || addgroup -S "$APP_GROUP"
  id "$APP_USER" >/dev/null 2>&1 ||
    adduser -S -D -h "$(dirname "$APP_DIR")" -G "$APP_GROUP" -s /bin/sh "$APP_USER"
  install -d -o "$APP_USER" -g "$APP_GROUP" "$(dirname "$APP_DIR")"
}

build_app() {
  [ "$(id -u)" -eq 0 ] || fail 'build must run as root; compilation is delegated to APP_USER'
  [ "$BUILD_FROM_SOURCE" = true ] ||
    fail 'set BUILD_FROM_SOURCE=true after installing the repository-pinned Ruby and Node.js runtimes'
  check_swap
  id "$APP_USER" >/dev/null 2>&1 || fail "application user is missing: $APP_USER"
  [ -d "$APP_DIR/.git" ] || fail "git source checkout is missing: $APP_DIR"

  su "$APP_USER" -s /bin/sh -c "
    set -eu
    cd '$APP_DIR'
    ruby -e 'abort unless RUBY_VERSION.start_with?(File.read(%q{.ruby-version}).strip)'
    node -e 'const n=+process.versions.node.split(\".\")[0]; process.exit(n >= 22 ? 0 : 1)'
    export RAILS_ENV=production NODE_ENV=production MAKEFLAGS=-j1 CMAKE_BUILD_PARALLEL_LEVEL=1
    bundle config set --local deployment true
    bundle config set --local without 'development test'
    bundle install --jobs 1 --retry 3
    bin/yarn install --immutable
    SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile
  "
}

case "$MODE" in
  check) require_alpine; check_swap ;;
  packages) require_alpine; install_packages ;;
  build) require_alpine; build_app ;;
  configure) require_alpine; exec "$APP_DIR/util/source-install/configure-1cpu-1gb.sh" apply ;;
  database) require_alpine; exec "$APP_DIR/util/source-install/configure-1cpu-1gb.sh" database-apply ;;
  *)
    printf 'Usage: %s {check|packages|build|configure|database}\n' "$PROGRAM" >&2
    exit 2
    ;;
esac
