# frozen_string_literal: true

class ActivityPub::ReactionsDistributionWorker < ActivityPub::RawDistributionWorker
  # Distribute reactions to servers that might have a copy
  # of the account in question
  def perform(json, source_account_id, target_inbox_url)
    @account        = Account.find(source_account_id)
    @json           = json

    @target_inboxes = if target_inbox_url.empty?
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
    @inboxes ||= (followers_inboxes + following_inboxes + @target_inboxes).uniq
  end

  def followers_inboxes
    @account.followers.inboxes
  end

  def following_inboxes
    @account.following.inboxes
  end

  def payload
    @json
  end
end
