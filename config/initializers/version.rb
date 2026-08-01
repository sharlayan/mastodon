# frozen_string_literal: true

Rails.application.config.after_initialize do
  Mastodon::Version.preload_git_state!
end
