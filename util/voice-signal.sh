#!/bin/sh
set -eu

PROGRAM="${0##*/}"
COMMAND="${1:-help}"

APP_DIR="${APP_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
APP_USER="${APP_USER:-$(stat -c %U "$APP_DIR")}"
APP_GROUP="${APP_GROUP:-$(id -gn "$APP_USER")}"
ENV_SOURCE="${ENV_SOURCE:-${APP_DIR}/.env.production}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
OPENRC_DIR="${OPENRC_DIR:-/etc/init.d}"
SERVICE="${SERVICE:-mastodon-voice-signal}"
WEB_SERVICE="${WEB_SERVICE:-mastodon-web}"
RESTART_WEB="${RESTART_WEB:-true}"
START_SERVICE="${START_SERVICE:-true}"
DRY_RUN="${DRY_RUN:-false}"
LOCAL_IMAGE="${LOCAL_IMAGE:-mastodon-voice-signal:local}"

SYSTEMD_UNIT="${SYSTEMD_DIR}/${SERVICE}.service"
WEB_DROP_IN="${SYSTEMD_DIR}/${WEB_SERVICE}.service.d/voice-signal.conf"
OPENRC_SCRIPT="${OPENRC_DIR}/${SERVICE}"
STYLES="service-binary service-docker puma-auto puma-binary puma-docker"

usage() {
  cat <<EOF
Usage:
  ${PROGRAM} check                  Report how the voice signal service is set up (read-only)
  ${PROGRAM} build                  Build voice_signal/publish/VoiceSignal (dotnet, or the .NET SDK container)
  ${PROGRAM} build-image            Build the container image locally as \$LOCAL_IMAGE
  ${PROGRAM} pull-image             Pull the container image named by VOICE_SIGNAL_IMAGE
  VOICE_SIGNAL_RUN=<style> ${PROGRAM} apply   Register the chosen way of running it (root)
  ${PROGRAM} verify                 Wait until the service answers its health check
  ${PROGRAM} remove                 Remove the dedicated service, the web drop-in and VOICE_SIGNAL_SPAWN (root)

Run styles (VOICE_SIGNAL_RUN):
  service-binary   Dedicated ${SERVICE} service running voice_signal/publish/VoiceSignal
  service-docker   Dedicated ${SERVICE} service running the container image
  puma-auto        Puma starts it: the local build when present, otherwise the container image
  puma-binary      Puma starts the local build
  puma-docker      Puma starts the container image

Overrides:
  APP_DIR (${APP_DIR}), APP_USER (${APP_USER}), APP_GROUP (${APP_GROUP})
  ENV_SOURCE (${ENV_SOURCE}), BUNDLE_BIN, SERVICE (${SERVICE}), WEB_SERVICE (${WEB_SERVICE})
  INIT_SYSTEM (systemd or openrc; detected), SYSTEMD_DIR (${SYSTEMD_DIR}), OPENRC_DIR (${OPENRC_DIR})
  LOCAL_IMAGE (${LOCAL_IMAGE})
  RESTART_WEB=false     Do not restart ${WEB_SERVICE} after changing its settings
  START_SERVICE=false   Register the dedicated service without starting it
  DRY_RUN=true          Write service files into non-default directories and print every other change
EOF
}

log() { printf '[%s] %s\n' "$PROGRAM" "$*"; }
fail() { printf '[%s] ERROR: %s\n' "$PROGRAM" "$*" >&2; exit 1; }

PROBLEMS=0
ok() { printf '  ok    %s\n' "$*"; }
warn() { printf '  warn  %s\n' "$*"; }
problem() { printf '  error %s\n' "$*"; PROBLEMS=$((PROBLEMS + 1)); }

assert_boolean() {
  case "$2" in
    true|false) ;;
    *) fail "$1 must be true or false (got: $2)" ;;
  esac
}

init_system() {
  if [ -n "${INIT_SYSTEM:-}" ]; then
    printf '%s' "$INIT_SYSTEM"
  elif command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    printf systemd
  elif command -v rc-service >/dev/null 2>&1; then
    printf openrc
  else
    printf none
  fi
}

require_root() {
  if [ "$DRY_RUN" = true ]; then
    [ "$SYSTEMD_DIR" != /etc/systemd/system ] && [ "$OPENRC_DIR" != /etc/init.d ] ||
      fail 'DRY_RUN=true needs SYSTEMD_DIR and OPENRC_DIR pointing somewhere other than the system directories'
    return
  fi
  [ "$(id -u)" -eq 0 ] || fail "${COMMAND} must run as root"
}

run() {
  if [ "$DRY_RUN" = true ]; then
    printf '  would run: %s\n' "$*"
  else
    "$@"
  fi
}

as_app_user() {
  local home
  if [ "$(id -u)" -ne 0 ] || [ "$APP_USER" = root ]; then
    "$@"
    return
  fi
  home="$(getent passwd "$APP_USER" | cut -d: -f6)"
  if command -v runuser >/dev/null 2>&1; then
    runuser -u "$APP_USER" -- env HOME="$home" "$@"
  else
    su "$APP_USER" -s /bin/sh -c "HOME=\"\$0\" exec \"\$@\"" "$home" "$@"
  fi
}

bundle_bin() {
  local candidate
  for candidate in "${BUNDLE_BIN:-}" "/home/${APP_USER}/.rbenv/shims/bundle" /usr/local/bin/bundle "$(command -v bundle || true)"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      printf '%s' "$candidate"
      return
    fi
  done
  fail 'bundle was not found; set BUNDLE_BIN'
}

env_value() {
  [ -r "$ENV_SOURCE" ] || return 0
  sed -n -E "s/^[[:space:]]*(export[[:space:]]+)?$1=//p" "$ENV_SOURCE" | tail -n 1 | sed -E -e 's/^"(.*)"$/\1/' -e "s/^'(.*)'$/\1/"
}

spawn_mode() {
  local value
  value="$(env_value VOICE_SIGNAL_SPAWN | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    ''|false|0|off|no) ;;
    *) printf '%s' "$value" ;;
  esac
}

signal_port() { local value; value="$(env_value VOICE_SIGNAL_PORT)"; printf '%s' "${value:-4100}"; }
signal_path() { local value; value="$(env_value VOICE_SIGNAL_PATH)"; value="${value:-/voice-signal}"; printf '/%s' "${value#/}" | sed 's:/*$::'; }
signal_image() { local value; value="$(env_value VOICE_SIGNAL_IMAGE)"; printf '%s' "${value:-ghcr.io/sharlayan/mastodon-voice-signal:edge}"; }

service_file() {
  case "$(init_system)" in
    systemd) printf '%s' "$SYSTEMD_UNIT" ;;
    openrc) printf '%s' "$OPENRC_SCRIPT" ;;
  esac
}

service_installed() {
  local file
  file="$(service_file)"
  [ -n "$file" ] && [ -f "$file" ]
}

service_enabled() {
  case "$(init_system)" in
    systemd) systemctl is-enabled --quiet "${SERVICE}.service" 2>/dev/null ;;
    openrc) rc-update show default 2>/dev/null | grep -qw "$SERVICE" ;;
    *) return 1 ;;
  esac
}

service_active() {
  case "$(init_system)" in
    systemd) systemctl is-active --quiet "${SERVICE}.service" 2>/dev/null ;;
    openrc) rc-service "$SERVICE" status >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

service_mode() {
  sed -n 's/.*bin\/voice-signal run --mode \([a-z]*\).*/\1/p' "$(service_file)" 2>/dev/null | head -n 1
}

binary_path() {
  local configured
  configured="$(env_value VOICE_SIGNAL_BINARY)"
  if [ -n "$configured" ]; then
    case "$configured" in
      /*) printf '%s' "$configured" ;;
      *) printf '%s/%s' "$APP_DIR" "$configured" ;;
    esac
  else
    printf '%s/voice_signal/publish/VoiceSignal' "$APP_DIR"
  fi
}

binary_ready() {
  local path
  path="$(binary_path)"
  case "$path" in
    *.dll) [ -f "$path" ] && command -v dotnet >/dev/null 2>&1 ;;
    *) [ -x "$path" ] ;;
  esac
}

docker_ready() {
  command -v docker >/dev/null 2>&1 && id -nG "$APP_USER" | tr ' ' '\n' | grep -qx docker
}

web_unit_text() {
  [ "$(init_system)" = systemd ] || return 0
  systemctl cat "${WEB_SERVICE}.service" 2>/dev/null || true
}

web_blocks_memfd() {
  local text
  text="$(web_unit_text)"
  printf '%s\n' "$text" | grep -q '^SystemCallFilter=~.*@ipc' && ! printf '%s\n' "$text" | grep -q '^SystemCallFilter=.*memfd_create'
}

web_private_users() {
  web_unit_text | sed -n 's/^PrivateUsers=//p' | tail -n 1 | grep -qx true
}

check_runtime() {
  local mode="$1"
  case "$mode" in
    binary)
      if binary_ready; then ok "local build: $(binary_path)"; else problem "no local build at $(binary_path) (run: ${PROGRAM} build)"; fi
      ;;
    docker)
      if docker_ready; then ok "docker is available to ${APP_USER}"; else problem "docker is missing or ${APP_USER} is not in the docker group"; fi
      if command -v docker >/dev/null 2>&1 && as_app_user docker image inspect "$(signal_image)" >/dev/null 2>&1; then
        ok "image present: $(signal_image)"
      else
        warn "image $(signal_image) is not present yet; it is pulled on first start (VOICE_SIGNAL_IMAGE_PULL)"
      fi
      ;;
    auto)
      if binary_ready; then
        ok "auto uses the local build: $(binary_path)"
      elif docker_ready; then
        ok 'auto uses the container image (no local build)'
        check_runtime docker
      else
        problem 'auto has neither a local build nor docker'
      fi
      ;;
    *)
      problem "unknown mode: ${mode}"
      ;;
  esac
}

check() {
  local mode path url installed=false
  log "app: ${APP_DIR}, user: ${APP_USER}, env: ${ENV_SOURCE}, init: $(init_system)"

  if [ -x "${APP_DIR}/bin/voice-signal" ]; then ok 'bin/voice-signal present'; else problem "${APP_DIR}/bin/voice-signal is missing"; fi
  if [ -r "$ENV_SOURCE" ]; then
    ok 'environment file readable'
    if [ -n "$(env_value SECRET_KEY_BASE)" ]; then ok 'SECRET_KEY_BASE set'; else problem "SECRET_KEY_BASE is not set in ${ENV_SOURCE}"; fi
    if [ -n "$(env_value LOCAL_DOMAIN)$(env_value WEB_DOMAIN)" ]; then ok 'LOCAL_DOMAIN/WEB_DOMAIN set'; else problem 'LOCAL_DOMAIN or WEB_DOMAIN must be set'; fi
  else
    problem "cannot read ${ENV_SOURCE}"
  fi

  path="$(signal_path)"
  url="$(env_value VOICE_SIGNAL_URL)"
  if [ -z "$url" ]; then
    ok "browsers use wss://<WEB_DOMAIN>${path}"
  else
    case "$url" in
      ws://*"${path}"|wss://*"${path}") ok "VOICE_SIGNAL_URL ends with ${path}" ;;
      *) problem "VOICE_SIGNAL_URL (${url}) does not end with VOICE_SIGNAL_PATH (${path})" ;;
    esac
  fi

  mode="$(spawn_mode)"
  service_installed && installed=true

  if [ -n "$mode" ] && [ "$installed" = true ] && { service_enabled || service_active; }; then
    problem "both Puma (VOICE_SIGNAL_SPAWN=${mode}) and the ${SERVICE} service are set to run it"
  fi

  if [ -n "$mode" ]; then
    log "style: Puma starts it (VOICE_SIGNAL_SPAWN=${mode})"
    check_runtime "$mode"
    if [ "$mode" != docker ] && web_blocks_memfd; then
      problem "${WEB_SERVICE} blocks memfd_create, which the .NET runtime needs (run apply, or add SystemCallFilter=memfd_create)"
    fi
    if [ "$mode" != binary ] && web_private_users && ! binary_ready; then
      warn "${WEB_SERVICE} uses PrivateUsers=true, which can hide the docker group from Puma (apply adds PrivateUsers=false)"
    fi
  elif [ "$installed" = true ]; then
    log "style: dedicated ${SERVICE} service ($(service_file))"
    mode="$(service_mode)"
    if [ -n "$mode" ]; then check_runtime "$mode"; fi
    if service_enabled; then ok 'service enabled at boot'; else warn 'service is not enabled at boot'; fi
    if service_active; then ok 'service running'; else problem 'service is not running'; fi
  else
    warn "not configured: set VOICE_SIGNAL_RUN and run apply (styles: ${STYLES})"
  fi

  if command -v curl >/dev/null 2>&1; then
    if curl --silent --fail --max-time 3 "http://127.0.0.1:$(signal_port)${path}/health" | grep -qx ok; then
      ok "health check answered on 127.0.0.1:$(signal_port)"
    else
      warn "no answer on http://127.0.0.1:$(signal_port)${path}/health"
    fi
  fi

  if [ -d /etc/nginx ]; then
    if grep -Erqs -- "location[[:space:]]+(\^~[[:space:]]+|=[[:space:]]+)?${path}" /etc/nginx; then
      ok "nginx has a location for ${path}"
    else
      warn "no nginx location for ${path} found (or not readable); browsers cannot reach the service without one"
    fi
  fi

  if [ "$PROBLEMS" -gt 0 ]; then
    log "${PROBLEMS} problem(s) found"
    return 1
  fi
  log 'no problems found'
}

edit_env() {
  local key="$1" value="${2:-}" backup tmp pattern
  pattern="^[[:space:]]*(export[[:space:]]+)?${key}="
  if [ -z "$value" ] && ! grep -qE "$pattern" "$ENV_SOURCE" 2>/dev/null; then
    return
  fi
  if [ -n "$value" ] && [ "$(env_value "$key")" = "$value" ]; then
    return
  fi

  if [ "$DRY_RUN" = true ]; then
    if [ -n "$value" ]; then printf '  would set %s=%s in %s\n' "$key" "$value" "$ENV_SOURCE"; else printf '  would remove %s from %s\n' "$key" "$ENV_SOURCE"; fi
    return
  fi

  [ -w "$ENV_SOURCE" ] || fail "cannot write ${ENV_SOURCE}"
  backup="${ENV_SOURCE}.voice-signal-$(date +%Y%m%d%H%M%S).bak"
  while [ -e "$backup" ]; do backup="${backup%.bak}-1.bak"; done
  cp -p "$ENV_SOURCE" "$backup"
  tmp="$(mktemp)"
  grep -vE "$pattern" "$ENV_SOURCE" >"$tmp" || true
  if [ -n "$value" ]; then printf '%s=%s\n' "$key" "$value" >>"$tmp"; fi
  cat "$tmp" >"$ENV_SOURCE"
  rm -f "$tmp"
  log "updated ${key} in ${ENV_SOURCE} (backup: ${backup})"
}

write_file() {
  local path="$1" mode="$2" content="$3"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" >"$path"
  chmod "$mode" "$path"
  log "wrote ${path}"
}

systemd_unit_content() {
  local mode="$1" after hardening
  after='network-online.target'
  if [ "$mode" = docker ]; then
    after="${after} docker.service"
    hardening='SupplementaryGroups=docker'
  else
    hardening='ProtectSystem=strict
ProtectHome=read-only
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictNamespaces=true
RestrictSUIDSGID=true
LockPersonality=true
SystemCallArchitectures=native
SystemCallFilter=@system-service
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK'
  fi

  cat <<EOF
[Unit]
Description=Mastodon voice signal (${mode})
After=${after}
Wants=network-online.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_GROUP}
WorkingDirectory=${APP_DIR}
Environment=RAILS_ENV=production
ExecStart=$(bundle_bin) exec bin/voice-signal run --mode ${mode}
Restart=always
RestartSec=5
TimeoutStopSec=20
KillSignal=SIGTERM
NoNewPrivileges=true
PrivateTmp=true
${hardening}

[Install]
WantedBy=multi-user.target
EOF
}

openrc_script_content() {
  local mode="$1" uses=''
  [ "$mode" != docker ] || uses=' docker'
  cat <<EOF
#!/sbin/openrc-run
name="Mastodon voice signal (${mode})"
directory="${APP_DIR}"
command="$(bundle_bin)"
command_args="exec bin/voice-signal run --mode ${mode}"
command_user="${APP_USER}:${APP_GROUP}"
command_background=true
pidfile="/run/${SERVICE}.pid"
start_stop_daemon_args="--env RAILS_ENV=production"
output_log="${APP_DIR}/log/voice-signal.log"
error_log="${APP_DIR}/log/voice-signal.log"
retry="TERM/20/KILL/5"

depend() {
  need net
  use${uses} postgresql
}
EOF
}

web_drop_in_content() {
  local mode="$1"
  printf '[Service]\nSystemCallFilter=memfd_create'
  if [ "$mode" != binary ] && getent group docker >/dev/null; then
    printf '\nPrivateUsers=false\nSupplementaryGroups=docker'
  fi
}

restart_web() {
  if [ "$RESTART_WEB" != true ]; then
    log "RESTART_WEB=false; restart ${WEB_SERVICE} to apply the change"
    return
  fi
  case "$(init_system)" in
    systemd)
      if [ "$DRY_RUN" = true ] || systemctl is-active --quiet "${WEB_SERVICE}.service"; then
        run systemctl restart "${WEB_SERVICE}.service"
      fi
      ;;
    openrc)
      if [ "$DRY_RUN" = true ] || rc-service "$WEB_SERVICE" status >/dev/null 2>&1; then
        run rc-service "$WEB_SERVICE" restart
      fi
      ;;
    *)
      log "restart ${WEB_SERVICE} to apply the change"
      ;;
  esac
}

remove_service() {
  case "$(init_system)" in
    systemd)
      if [ -f "$SYSTEMD_UNIT" ]; then
        run systemctl disable --now "${SERVICE}.service"
        run rm -f "$SYSTEMD_UNIT"
        run systemctl daemon-reload
      fi
      ;;
    openrc)
      if [ -f "$OPENRC_SCRIPT" ]; then
        run rc-service "$SERVICE" stop
        run rc-update del "$SERVICE" default
        run rm -f "$OPENRC_SCRIPT"
      fi
      ;;
  esac
}

remove_web_drop_in() {
  [ "$(init_system)" = systemd ] && [ -f "$WEB_DROP_IN" ] || return 0
  run rm -f "$WEB_DROP_IN"
  run systemctl daemon-reload
}

install_service() {
  local mode="$1"
  case "$(init_system)" in
    systemd)
      write_file "$SYSTEMD_UNIT" 644 "$(systemd_unit_content "$mode")"
      if [ "$DRY_RUN" = true ]; then
        systemd-analyze verify "$SYSTEMD_UNIT" || true
      fi
      run systemctl daemon-reload
      run systemctl enable "${SERVICE}.service"
      if [ "$START_SERVICE" = true ]; then run systemctl restart "${SERVICE}.service"; fi
      ;;
    openrc)
      write_file "$OPENRC_SCRIPT" 755 "$(openrc_script_content "$mode")"
      run rc-update add "$SERVICE" default
      if [ "$START_SERVICE" = true ]; then run rc-service "$SERVICE" restart; fi
      ;;
    *)
      fail 'neither systemd nor OpenRC is available; use a puma-* style instead'
      ;;
  esac
}

apply() {
  local style="${VOICE_SIGNAL_RUN:-}" mode
  require_root
  assert_boolean RESTART_WEB "$RESTART_WEB"
  assert_boolean START_SERVICE "$START_SERVICE"
  [ -n "$style" ] || fail "set VOICE_SIGNAL_RUN to one of: ${STYLES}"
  [ -r "$ENV_SOURCE" ] || fail "cannot read ${ENV_SOURCE}"
  mode="${style#*-}"

  case "$style" in
    service-binary|service-docker|puma-auto|puma-binary|puma-docker) ;;
    *) fail "unknown VOICE_SIGNAL_RUN: ${style} (expected one of: ${STYLES})" ;;
  esac
  [ "$mode" != binary ] || binary_ready || fail "no local build at $(binary_path); run '${PROGRAM} build' first"
  [ "$mode" != docker ] || docker_ready || fail "docker is missing or ${APP_USER} is not in the docker group"
  [ "$mode" != auto ] || binary_ready || docker_ready || fail 'auto needs a local build or docker'

  case "$style" in
    service-*)
      edit_env VOICE_SIGNAL_SPAWN ''
      remove_web_drop_in
      restart_web
      install_service "$mode"
      ;;
    puma-*)
      remove_service
      if [ "$(init_system)" = systemd ]; then
        write_file "$WEB_DROP_IN" 644 "$(web_drop_in_content "$mode")"
        run systemctl daemon-reload
      fi
      edit_env VOICE_SIGNAL_SPAWN "$mode"
      restart_web
      ;;
  esac

  if [ "$DRY_RUN" = true ]; then
    log 'dry run finished'
  else
    log "applied ${style}; run '${PROGRAM} verify' to wait for the health check"
  fi
}

remove() {
  require_root
  remove_service
  remove_web_drop_in
  edit_env VOICE_SIGNAL_SPAWN ''
  restart_web
  log 'voice signal registration removed'
}

verify() {
  local attempt=0 url
  command -v curl >/dev/null 2>&1 || fail 'verify needs curl'
  url="http://127.0.0.1:$(signal_port)$(signal_path)/health"
  while [ "$attempt" -lt 15 ]; do
    attempt=$((attempt + 1))
    if curl --silent --fail --max-time 3 "$url" | grep -qx ok; then
      log "voice signal answers on ${url}"
      return
    fi
    sleep 2
  done
  fail "no answer from ${url}"
}

case "$COMMAND" in
  -h|--help|help) usage ;;
  check) check ;;
  build)
    cd "$APP_DIR"
    as_app_user env RAILS_ENV=production "$(bundle_bin)" exec bin/voice-signal build
    ;;
  build-image)
    command -v docker >/dev/null 2>&1 || fail 'docker is not installed'
    docker build --file "${APP_DIR}/voice_signal/Dockerfile" --tag "$LOCAL_IMAGE" "$APP_DIR"
    log "built ${LOCAL_IMAGE}; set VOICE_SIGNAL_IMAGE=${LOCAL_IMAGE} and VOICE_SIGNAL_IMAGE_PULL=never in ${ENV_SOURCE} to use it"
    ;;
  pull-image)
    command -v docker >/dev/null 2>&1 || fail 'docker is not installed'
    as_app_user docker pull "$(signal_image)"
    ;;
  apply) apply ;;
  verify) verify ;;
  remove) remove ;;
  *) usage >&2; fail "unknown command: ${COMMAND}" ;;
esac
