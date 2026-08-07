#!/bin/bash
ENV_FILE=".env.production"
RUBY_VERSION=$(cat .ruby-version)

rails_export () {
  export LD_PRELOAD=/lib/x86_64-linux-gnu/libjemalloc.so.2

  eval "$(rbenv init -)"

  export NODE_OPTIONS=--openssl-legacy-provider
  export PATH="/home/mastodon/.rbenv/bin:$PATH"
  export RAILS_ENV=production
  export NODE_ENV=production
}

debug_migrate () {
  rails_export
  bundle exec rails db:migrate --trace
}

debug_web () {
  rails_export
  RAILS_LOG_LEVEL=debug bundle exec rails s
}

debug_webpack () {
  rails_export
  ./bin/vite dev
}

debug_sidekiq () {
  rails_export
  RAILS_LOG_LEVEL=debug bundle exec sidekiq -c 4
}

debug_streaming () {
  NODE_ENV=production PORT=4000 node ./streaming
}

debug_console () {
  rails_export
  bundle exec rails console
}

clear_cache () {
  rails_export
  bundle exec rails runner "Rails.cache.clear"
  echo -e "\033[32m[cache]\033[0m Rails 캐시 클리어 완료"
}

build_web () {
  rails_export

  yarn install

  bundle install
  bundle exec rails assets:precompile --trace

  debug_migrate
  clear_cache
}

instance_info() {
  rails_export
  bundle exec rails instance_metadata:initialize
}

feeds_rebuild() {
  rails_export
  bundle exec bin/tootctl feeds build --all
}

restart_web() {
  rails_export
  echo -e "\033[36m[web]\033[0m 프로세스 검색 중..."
  if pgrep -f "bundle exec rails s" > /dev/null 2>&1; then
    pkill -f "bundle exec rails s"
    echo -e "\033[33m[web]\033[0m 종료됨, 재시작 중..."
    sleep 1
  else
    echo -e "\033[33m[web]\033[0m 실행 중인 프로세스 없음, 새로 시작..."
  fi
  RAILS_LOG_LEVEL=debug bundle exec rails s &
  echo -e "\033[32m[web]\033[0m 시작됨 (PID: $!)"
}

restart_sidekiq() {
  rails_export
  echo -e "\033[36m[sidekiq]\033[0m 프로세스 검색 중..."
  if pgrep -f "bundle exec sidekiq" > /dev/null 2>&1; then
    pkill -f "bundle exec sidekiq"
    echo -e "\033[33m[sidekiq]\033[0m 종료됨, 재시작 중..."
    sleep 1
  else
    echo -e "\033[33m[sidekiq]\033[0m 실행 중인 프로세스 없음, 새로 시작..."
  fi
  RAILS_LOG_LEVEL=debug bundle exec sidekiq -c 4 &
  echo -e "\033[32m[sidekiq]\033[0m 시작됨 (PID: $!)"
}

restart_streaming() {
  echo -e "\033[36m[streaming]\033[0m 프로세스 검색 중..."
  if pgrep -f "node ./streaming" > /dev/null 2>&1; then
    pkill -f "node ./streaming"
    echo -e "\033[33m[streaming]\033[0m 종료됨, 재시작 중..."
    sleep 1
  else
    echo -e "\033[33m[streaming]\033[0m 실행 중인 프로세스 없음, 새로 시작..."
  fi
  NODE_ENV=production PORT=4000 node ./streaming &
  echo -e "\033[32m[streaming]\033[0m 시작됨 (PID: $!)"
}

restart_all() {
  restart_web
  restart_sidekiq
  restart_streaming
}

bundle_remove_without () {
  bundle config --delete without
  bundle install
}

show_help () {
  echo -e "\033[36mUsage:\033[0m bash build.sh <command>"
  echo ""
  echo -e "\033[36mCommands:\033[0m"
  echo -e "  \033[33mweb\033[0m        - Rails 웹 서버 (디버그 모드)"
  echo -e "  \033[33mstreaming\033[0m  - Node.js 스트리밍 서버"
  echo -e "  \033[33mwebpack\033[0m    - Vite 개발 서버"
  echo -e "  \033[33msidekiq\033[0m    - Sidekiq 워커 (디버그 모드)"
  echo -e "  \033[33mconsole\033[0m    - Rails 콘솔"
  echo -e "  \033[33mmigrate\033[0m    - DB 마이그레이션 (trace)"
  echo -e "  \033[33mbuild\033[0m      - 전체 빌드 (bundle + assets + migrate)"
  echo -e "  \033[33mbundle\033[0m     - Bundle without 설정 제거 후 재설치"
  echo -e "  \033[33minfo\033[0m       - 인스턴스 메타데이터 초기화"
  echo -e "  \033[33mfeeds\033[0m        - 모든 사용자 피드 재빌드 (tootctl feeds build --all)"
  echo -e "  \033[33mrestart-web\033[0m  - 웹 서버 재시작 (백그라운드)"
  echo -e "  \033[33mrestart-sidekiq\033[0m - Sidekiq 재시작 (백그라운드)"
  echo -e "  \033[33mrestart-streaming\033[0m - 스트리밍 서버 재시작 (백그라운드)"
  echo -e "  \033[33mrestart-all\033[0m  - web + sidekiq + streaming 모두 재시작"
  echo -e "  \033[33mhelp\033[0m         - 이 도움말 표시"
}

pwd

echo -e " * Current Config"
echo -e " * dotenv            : \033[33m$ENV_FILE \033[0m"
echo -e " * Web Port          : \033[33m$WEB_PORT \033[0m"
echo -e " * Streaming Port    : \033[33m$STREAMING_PORT \033[0m"
echo -e " * Bind              : \033[33m$BIND \033[0m"

if [[ $# -eq 0 ]]; then
  show_help
else
  arg=""
  count=0
  for v in "$@"
  do
    if [[ count -ne 0 ]]; then
      arg="$arg ${v}"
    fi
    let count+=1
  done
  case "$1" in
  web)
    debug_web
    ;;
  streaming)
    debug_streaming
    ;;
  webpack)
    debug_webpack
    ;;
  sidekiq)
    debug_sidekiq
    ;;
  console)
    debug_console
    ;;
  info)
    instance_info
    ;;
  restart-web)
    restart_web
    ;;
  restart-sidekiq)
    restart_sidekiq
    ;;
  restart-streaming)
    restart_streaming
    ;;
  restart-all)
    restart_all
    ;;
  feeds)
    feeds_rebuild
    ;;
  migrate)
    debug_migrate
    ;;
  build)
    build_web
    ;;
  bundle)
    bundle_remove_without
    ;;
  help)
    show_help
    ;;
  *)
    echo -e "\033[31mUnknown command:\033[0m $1"
    echo ""
    show_help
    ;;
  esac
fi
