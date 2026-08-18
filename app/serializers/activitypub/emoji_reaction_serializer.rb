# frozen_string_literal: true

class ActivityPub::EmojiReactionSerializer < ActivityPub::Serializer
  attributes :id, :type, :actor, :content, :_misskey_reaction
  attribute :virtual_object, key: :object
  attribute :custom_emoji, key: :tag, unless: -> { object.custom_emoji.nil? }

  def id
    [ActivityPub::TagManager.instance.uri_for(object.account), '#emoji_reactions/', object.id].join
  end

  def type
    'Like'
  end

  def actor
    ActivityPub::TagManager.instance.uri_for(object.account)
  end

  def _misskey_reaction
    content.to_s
  end

  def virtual_object
    ActivityPub::TagManager.instance.uri_for(object.status)
  end

  def content
    if object.custom_emoji.nil?
      object.name
    else
      ":#{object.name}:"
    end
  end

  alias reaction content

  def custom_emoji
    [ActivityPub::EmojiSerializer.new(object.custom_emoji).serializable_hash]
  end
end
