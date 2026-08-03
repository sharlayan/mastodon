# frozen_string_literal: true

class PurgeBrokenCustomEmojiWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'pull', retry: 0

  def perform(dry_run = true) # rubocop:disable Style/OptionalBooleanParameter
    purged = 0

    CustomEmoji.local.reorder(nil).find_each do |emoji|
      next if emoji.image.exists?

      if dry_run
        Rails.logger.info("[PurgeBrokenCustomEmoji] would purge :#{emoji.shortcode}: (id=#{emoji.id})")
      else
        emoji.destroy
      end

      purged += 1
    end

    Rails.logger.info("[PurgeBrokenCustomEmoji] #{dry_run ? 'would purge' : 'purged'} #{purged} broken local custom emoji")

    purged
  end
end
