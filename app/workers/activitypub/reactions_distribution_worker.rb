# frozen_string_literal: true

class ActivityPub::ReactionsDistributionWorker < ActivityPub::RawDistributionWorker
  # Distribute reactions to servers that might have a copy
  # of the account in question
  def perform(json, source_account_id, target_inbox_url, status_account_id = nil)
    @account        = Account.find(source_account_id)
    @json           = json
    @status_account = status_account_id.present? ? Account.find(status_account_id) : @account

    @target_inboxes = if target_inbox_url.to_s.empty?
                        []
                      else
                        [target_inbox_url]
                      end

    distribute!
  rescue ActiveRecord::RecordNotFound
    true
  end

  protected

  def inboxes
    @inboxes ||= (status_followers_inboxes + @target_inboxes).uniq
  end

  def status_followers_inboxes
    @status_account.followers.inboxes
  end

  def payload
    @json
  end
end
