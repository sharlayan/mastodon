# frozen_string_literal: true

namespace :custom_emoji_mutes do
  desc 'Warm the external-client custom emoji mute cache'
  task warm_cache: :environment do
    Account.where.associated(:custom_emoji_mutes).distinct.in_batches do |accounts|
      accounts.pluck(:id).each { |account_id| CustomEmojiMuteCache.write(account_id) }
    end
  end
end
