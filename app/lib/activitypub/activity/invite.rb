# frozen_string_literal: true

class ActivityPub::Activity::Invite < ActivityPub::Activity
  def perform
    Sharlayan::ChatFederation::Incoming.handle_invite(@json, @account)
  end
end