# frozen_string_literal: true

module Sharlayan
  class LimitedReplyScope
    def self.prepare!(account:, options:, thread:, visibility:, quoted_status: nil)
      raise Mastodon::ValidationError, I18n.t('statuses.errors.invalid_reply_scope') unless options[:limited_scope].to_s == 'reply' && %w(private limited).include?(visibility.to_s) && options[:circle_id].blank? && thread&.limited_visibility?
      raise Mastodon::NotPermittedError unless StatusPolicy.new(account, thread).reply?
      raise Mastodon::ValidationError, I18n.t('statuses.errors.reply_scope_quote') if quoted_status.present?

      account_ids = (thread.mentions.pluck(:account_id) + [thread.account_id, account.id]).uniq
      account_ids &= Array(options[:limited_reply_account_ids]).map(&:to_i) if options[:limited_reply_account_ids]
      options[:limited_reply_account_ids] = account_ids.map(&:to_s)
      options[:local_only] = true if thread.local_only?
    end

    def self.listed_account_ids(status)
      account_ids = status.mentions.pluck(:account_id)
      listed_ids = status.active_mentions.pluck(:account_id) + [status.in_reply_to_account_id]
      listed_ids += status.thread.active_mentions.pluck(:account_id) if status.thread
      ::Account.without_suspended.where(id: account_ids & listed_ids.compact).pluck(:id)
    end
  end
end
