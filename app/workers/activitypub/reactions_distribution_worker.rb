# frozen_string_literal: true

class ActivityPub::ReactionsDistributionWorker < ActivityPub::RawDistributionWorker
  def perform(json, source_account_id, target_inbox_url = '')
    @account        = Account.find(source_account_id)
    @json           = json
    @target_inboxes = target_inbox_url.to_s.empty? ? [] : [target_inbox_url]

    distribute!
  rescue ActiveRecord::RecordNotFound
    true
  end

  protected

  def inboxes
    @inboxes ||= (@account.followers.inboxes + @target_inboxes).uniq
  end

  def payload
    @json
  end
end
