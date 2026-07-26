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

require_debian() {
  [ -f /etc/debian_version ] || fail 'this helper supports Debian-family systems only'
}

check_swap() {
  swap_mib=$(awk '/^SwapTotal:/ { print int($2 / 1024) }' /proc/meminfo)
  [ "$swap_mib" -ge "$MIN_SWAP_MIB" ] ||
    fail "at least ${MIN_SWAP_MIB} MiB swap is required for a 1 GiB source build (found ${swap_mib} MiB)"
}

install_packages() {
  [ "$(id -u)" -eq 0 ] || fail 'packages must run as root'
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl ffmpeg git imagemagick libffi-dev \
    libgdbm-dev libicu-dev libidn-dev libjemalloc2 libpq-dev libreadline-dev \
    libssl-dev libvips-dev libyaml-dev pkg-config postgresql postgresql-contrib \
    redis-server rustc zlib1g-dev
  getent group "$APP_GROUP" >/dev/null || groupadd --system "$APP_GROUP"
  id "$APP_USER" >/dev/null 2>&1 ||
    useradd --system --create-home --gid "$APP_GROUP" --shell /bin/bash "$APP_USER"
  install -d -o "$APP_USER" -g "$APP_GROUP" "$(dirname "$APP_DIR")"
}

build_app() {
  [ "$(id -u)" -eq 0 ] || fail 'build must run as root; compilation is delegated to APP_USER'
  [ "$BUILD_FROM_SOURCE" = true ] ||
    fail 'set BUILD_FROM_SOURCE=true after installing the repository-pinned Ruby and Node.js runtimes'
  check_swap
  id "$APP_USER" >/dev/null 2>&1 || fail "application user is missing: $APP_USER"
  [ -d "$APP_DIR/.git" ] || fail "git source checkout is missing: $APP_DIR"

  runuser -u "$APP_USER" -- sh -lc "
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
  check) require_debian; check_swap ;;
  packages) require_debian; install_packages ;;
  build) require_debian; build_app ;;
  configure) require_debian; exec "$APP_DIR/util/source-install/configure-1cpu-1gb.sh" apply ;;
  database) require_debian; exec "$APP_DIR/util/source-install/configure-1cpu-1gb.sh" database-apply ;;
  *)
    printf 'Usage: %s {check|packages|build|configure|database}\n' "$PROGRAM" >&2
    exit 2
    ;;
esac
