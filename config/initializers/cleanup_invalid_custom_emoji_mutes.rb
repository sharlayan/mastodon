# frozen_string_literal: true

Rails.application.config.after_initialize do
  next if defined?(Rails::Console)
  next unless ActiveRecord::Base.connection.data_source_exists?('custom_emoji_mutes')

  CustomEmojiMute.purge_blank_prefixes!
rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid, PG::ConnectionBad
  nil
end
