#!/bin/bash
ENV_FILE=".env.production"
RUBY_VERSION=$(cat .ruby-version)

rails_export () {
  # for ruby rails command error...
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

build_web () {
  rails_export

  bundle install
  bundle exec rails assets:precompile --trace

  debug_migrate
}

instance_info() {
  rails_export
  bundle exec rails instance_metadata:initialize
}

bundle_remove_without () {
  bundle config --delete without
  bundle install
}

pwd

echo -e " * Current Config"
echo -e " * dotenv            : \033[33m$ENV_FILE \033[0m"
echo -e " * Web Port          : \033[33m$WEB_PORT \033[0m"
echo -e " * Streaming Port    : \033[33m$STREAMING_PORT \033[0m"
echo -e " * Bind              : \033[33m$BIND \033[0m"

if [[ $# -eq 0 ]]; then
  # debug_web
  echo "no args received"
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
  webpack)
    debug_webpack
    ;;
  sidekiq)
    debug_sidekiq
    ;;
  info)
    instance_info
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
  *)
    echo -e "arg no match"
    ;;
  esac
fi
