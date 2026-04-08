# frozen_string_literal: true

class ActivityPub::AcceptFollowSerializer < ActivityPub::Serializer
  context_extensions :followed_message

  attributes :id, :type, :actor
  attribute :followed_message, key: :followedMessage, if: :followed_message?

  has_one :object, serializer: ActivityPub::FollowSerializer

  def id
    [ActivityPub::TagManager.instance.uri_for(object.target_account), '#accepts/follows/', object.id].join
  end

  def type
    'Accept'
  end

  def actor
    ActivityPub::TagManager.instance.uri_for(object.target_account)
  end

  def followed_message
    object.target_account.followed_message
  end

  def followed_message?
    object.target_account.followed_message.present?
  end
end
