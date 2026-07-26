#!/bin/sh
set -eu

PROGRAM=${0##*/}
MODE=${1:-check}
APP_USER=${APP_USER:-mastodon}
APP_GROUP=${APP_GROUP:-mastodon}
APP_DIR=${APP_DIR:-/home/mastodon/live}
ENV_FILE=${ENV_FILE:-$APP_DIR/.env.production}
PROFILE_SOURCE=${PROFILE_SOURCE:-$APP_DIR/util/source-install/1cpu-1gb.env}
PROFILE_TARGET=${PROFILE_TARGET:-/etc/mastodon/1cpu-1gb.env}
RUBY_BIN=${RUBY_BIN:-$(command -v ruby || true)}
BUNDLE_BIN=${BUNDLE_BIN:-$(command -v bundle || true)}
NODE_BIN=${NODE_BIN:-$(command -v node || true)}
RESTART_DATABASE=${RESTART_DATABASE:-true}

log() {
  printf '[%s] %s\n' "$PROGRAM" "$*"
}

fail() {
  printf '[%s] ERROR: %s\n' "$PROGRAM" "$*" >&2
  exit 1
}

require_root() {
  [ "$(id -u)" -eq 0 ] || fail 'apply and verify must run as root'
}

postgres_exec() {
  if command -v runuser >/dev/null 2>&1; then
    runuser -u postgres -- psql -v ON_ERROR_STOP=1 "$@"
  else
    su postgres -s /bin/sh -c 'psql -v ON_ERROR_STOP=1 "$@"' sh "$@"
  fi
}

restart_postgres() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart postgresql.service
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service postgresql restart
  else
    fail 'neither systemd nor OpenRC is available'
  fi
}

database_check() {
  require_root
  command -v psql >/dev/null 2>&1 || fail 'PostgreSQL client is not installed'
  command -v pg_isready >/dev/null 2>&1 || fail 'pg_isready is not installed'
  pg_isready -q || fail 'PostgreSQL is not accepting local connections'

  matches=$(postgres_exec -Atqc "
    SELECT
      current_setting('shared_buffers') = '64MB'
      AND current_setting('effective_cache_size') = '256MB'
      AND current_setting('work_mem') = '2MB'
      AND current_setting('maintenance_work_mem') = '32MB'
      AND current_setting('max_connections') = '30'
      AND current_setting('autovacuum_max_workers') = '2'
      AND current_setting('autovacuum_work_mem') = '32MB'
      AND current_setting('max_wal_size') = '512MB'
      AND current_setting('checkpoint_timeout') = '15min'
      AND current_setting('checkpoint_completion_target') = '0.9'
      AND current_setting('jit') = 'off';
  ")
  [ "$matches" = t ] || fail 'PostgreSQL 1GB profile does not match'

  pending=$(postgres_exec -Atqc "
    SELECT count(*) FROM pg_settings
    WHERE pending_restart
      AND name IN ('shared_buffers', 'max_connections', 'autovacuum_max_workers');
  ")
  [ "$pending" -eq 0 ] || fail "$pending PostgreSQL settings require a restart"
  log 'PostgreSQL 1GB profile verified'
}

database_apply() {
  require_root
  case "$RESTART_DATABASE" in
    true|false) ;;
    *) fail "RESTART_DATABASE must be true or false (found $RESTART_DATABASE)" ;;
  esac
  command -v psql >/dev/null 2>&1 || fail 'PostgreSQL client is not installed'
  command -v pg_isready >/dev/null 2>&1 || fail 'pg_isready is not installed'
  pg_isready -q || fail 'start and initialize PostgreSQL before database-apply'

  postgres_exec <<'SQL'
ALTER SYSTEM SET shared_buffers = '64MB';
ALTER SYSTEM SET effective_cache_size = '256MB';
ALTER SYSTEM SET work_mem = '2MB';
ALTER SYSTEM SET maintenance_work_mem = '32MB';
ALTER SYSTEM SET max_connections = '30';
ALTER SYSTEM SET autovacuum_max_workers = '2';
ALTER SYSTEM SET autovacuum_work_mem = '32MB';
ALTER SYSTEM SET max_wal_size = '512MB';
ALTER SYSTEM SET min_wal_size = '80MB';
ALTER SYSTEM SET checkpoint_timeout = '15min';
ALTER SYSTEM SET checkpoint_completion_target = '0.9';
ALTER SYSTEM SET jit = 'off';
SQL

  if [ "$RESTART_DATABASE" = true ]; then
    restart_postgres
    database_check
  else
    postgres_exec -qc 'SELECT pg_reload_conf();'
    log 'PostgreSQL profile applied; restart is still required'
  fi
}

check() {
  [ -d "$APP_DIR" ] || fail "source tree not found: $APP_DIR"
  [ -f "$APP_DIR/Gemfile.lock" ] || fail 'Gemfile.lock is missing'
  [ -f "$APP_DIR/streaming/index.js" ] || fail 'streaming source is missing'
  [ -f "$ENV_FILE" ] || fail "production environment is missing: $ENV_FILE"
  [ -f "$PROFILE_SOURCE" ] || fail "low-resource profile is missing: $PROFILE_SOURCE"
  [ -n "$RUBY_BIN" ] && [ -x "$RUBY_BIN" ] || fail 'Ruby is not installed'
  [ -n "$BUNDLE_BIN" ] && [ -x "$BUNDLE_BIN" ] || fail 'Bundler is not installed'
  [ -n "$NODE_BIN" ] && [ -x "$NODE_BIN" ] || fail 'Node.js is not installed'

  ruby_version=$("$RUBY_BIN" -e 'print RUBY_VERSION')
  case "$ruby_version" in
    4.*) ;;
    *) fail "Ruby 4.x is required (found $ruby_version)" ;;
  esac

  node_major=$("$NODE_BIN" -p 'process.versions.node.split(".")[0]')
  [ "$node_major" -ge 22 ] || fail "Node.js 22+ is required (found $("$NODE_BIN" -v))"
  (cd "$APP_DIR" && "$BUNDLE_BIN" check) >/dev/null 2>&1 ||
    fail 'locked production gems are not installed'
  [ -d "$APP_DIR/node_modules" ] || fail 'node_modules is not installed'
  [ -d "$APP_DIR/public/packs" ] || fail 'production assets are not compiled'

  log "check passed: Ruby $ruby_version, Node $("$NODE_BIN" -v)"
}

install_profile() {
  install -d -m 755 /etc/mastodon
  install -m 644 "$PROFILE_SOURCE" "$PROFILE_TARGET"
  install -d -o "$APP_USER" -g "$APP_GROUP" \
    "$APP_DIR/log" "$APP_DIR/tmp" "$APP_DIR/public/system"
  chmod 600 "$ENV_FILE"
}

write_systemd_units() {
  command -v systemctl >/dev/null 2>&1 || return 1

  for service in web sidekiq streaming; do
    case "$service" in
      web)
        description='Mastodon web'
        command="$BUNDLE_BIN exec puma -C config/puma.rb"
        extra_environment=
        memory_limits='MemoryHigh=520M
MemoryMax=650M'
        ;;
      sidekiq)
        description='Mastodon Sidekiq'
        command="$BUNDLE_BIN exec sidekiq -c 1"
        extra_environment='Environment=RUBY_YJIT_ENABLE=0
Environment=DB_POOL=2'
        memory_limits='MemoryHigh=400M
MemoryMax=500M'
        ;;
      streaming)
        description='Mastodon streaming'
        command="$NODE_BIN ./streaming/index.js"
        extra_environment='Environment=PORT=4000
Environment=DB_POOL=2'
        memory_limits='MemoryHigh=160M
MemoryMax=220M'
        ;;
    esac

    unit=/etc/systemd/system/mastodon-$service.service
    {
      printf '%s\n' '[Unit]'
      printf 'Description=%s\n' "$description"
      printf '%s\n' 'After=network-online.target postgresql.service redis-server.service' \
        'Wants=network-online.target' '' '[Service]' 'Type=simple'
      printf 'User=%s\nGroup=%s\nWorkingDirectory=%s\n' "$APP_USER" "$APP_GROUP" "$APP_DIR"
      printf 'EnvironmentFile=%s\nEnvironmentFile=%s\n' "$ENV_FILE" "$PROFILE_TARGET"
      [ -z "$extra_environment" ] || printf '%s\n' "$extra_environment"
      printf 'ExecStart=%s\n' "$command"
      printf '%s\n' 'Restart=on-failure' 'RestartSec=3' 'TimeoutStopSec=30'
      printf '%s\n' "$memory_limits"
      printf '%s\n' 'OOMPolicy=stop' '' '[Install]' \
        'WantedBy=multi-user.target'
    } >"$unit"
  done

  systemctl daemon-reload
  systemd-analyze verify \
    /etc/systemd/system/mastodon-web.service \
    /etc/systemd/system/mastodon-sidekiq.service \
    /etc/systemd/system/mastodon-streaming.service
  systemctl enable mastodon-web mastodon-sidekiq mastodon-streaming
}

write_openrc_units() {
  command -v rc-service >/dev/null 2>&1 || return 1

  install -d -m 755 /usr/local/libexec
  runner=/usr/local/libexec/mastodon-source-run
  {
    printf '%s\n' '#!/bin/sh' 'set -eu' 'service=$1' 'set -a'
    printf '. %s\n. %s\n' "$ENV_FILE" "$PROFILE_TARGET"
    printf '%s\n' 'set +a' 'cd '"$APP_DIR"
    printf '%s\n' 'case "$service" in'
    printf '  web) exec %s exec puma -C config/puma.rb ;;\n' "$BUNDLE_BIN"
    printf '  sidekiq) export RUBY_YJIT_ENABLE=0 DB_POOL=2; exec %s exec sidekiq -c 1 ;;\n' "$BUNDLE_BIN"
    printf '  streaming) export PORT=4000 DB_POOL=2; exec %s ./streaming/index.js ;;\n' "$NODE_BIN"
    printf '%s\n' '  *) exit 64 ;;' 'esac'
  } >"$runner"
  chmod 755 "$runner"

  for service in web sidekiq streaming; do
    init=/etc/init.d/mastodon-$service
    {
      printf '%s\n' '#!/sbin/openrc-run'
      printf 'name="Mastodon %s"\n' "$service"
      printf 'directory="%s"\ncommand="%s"\n' "$APP_DIR" "$runner"
      printf 'command_args="%s"\ncommand_user="%s:%s"\n' "$service" "$APP_USER" "$APP_GROUP"
      printf 'command_background=true\npidfile="/run/mastodon-%s.pid"\n' "$service"
      printf 'output_log="%s/log/%s.log"\nerror_log="%s/log/%s.log"\n' "$APP_DIR" "$service" "$APP_DIR" "$service"
      printf 'depend() { need net; use postgresql redis; }\n'
    } >"$init"
    chmod 755 "$init"
    rc-update add mastodon-$service default
  done
}

apply() {
  require_root
  check
  install_profile
  if write_systemd_units; then
    log 'installed and enabled systemd units; start them after database setup'
  elif write_openrc_units; then
    log 'installed and enabled OpenRC services; start them after database setup'
  else
    fail 'neither systemd nor OpenRC is available'
  fi
}

verify() {
  require_root
  check
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active --quiet mastodon-web mastodon-sidekiq mastodon-streaming ||
      fail 'one or more Mastodon systemd services are inactive'
  elif command -v rc-service >/dev/null 2>&1; then
    for service in web sidekiq streaming; do
      rc-service mastodon-$service status >/dev/null ||
        fail "mastodon-$service is inactive"
    done
  else
    fail 'neither systemd nor OpenRC is available'
  fi
  log 'verification passed'
}

case "$MODE" in
  check) check ;;
  apply) apply ;;
  verify) verify ;;
  database-check) database_check ;;
  database-apply) database_apply ;;
  *)
    printf 'Usage: %s {check|apply|verify|database-check|database-apply}\n' "$PROGRAM" >&2
    exit 2
    ;;
esac
