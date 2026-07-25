# frozen_string_literal: true

class ActivityPub::ActorSerializer < ActivityPub::Serializer
  include RoutingHelper
  include FormattingHelper

  context :security, :webfinger

  context_extensions :manually_approves_followers, :featured, :also_known_as,
                     :moved_to, :property_value, :discoverable, :suspended,
                     :memorial, :indexable, :attribution_domains, :profile_settings,
                     :misskey_followed_message, :avatar_decorations, :is_cat

  context_extensions :interaction_policies

  attributes :id, :webfinger, :type, :following, :followers,
             :inbox, :outbox, :featured, :featured_tags,
             :preferred_username, :name, :summary,
             :url, :manually_approves_followers,
             :discoverable, :indexable, :published, :memorial,
             :show_featured, :show_media

  attribute :show_media_replies, key: :show_replies_in_media

  attribute :interaction_policy
  attribute :featured_collections

  has_one :keypair, key: :public_key, serializer: ActivityPub::PublicKeySerializer

  has_many :virtual_tags, key: :tag
  has_many :virtual_attachments, key: :attachment

  attribute :moved_to, if: :moved?
  attribute :also_known_as, if: :also_known_as?
  attribute :suspended, if: :suspended?
  attribute :attribution_domains, if: -> { object.attribution_domains.any? }
  attribute :misskey_followed_message, key: :_misskey_followedMessage, if: :followed_message?
  attribute :misskey_avatar_decorations, key: :_misskey_avatarDecorations, if: :avatar_decorations_enabled?
  attribute :is_cat, key: :isCat, if: :cat?

  class EndpointsSerializer < ActivityPub::Serializer
    include RoutingHelper

    attributes :shared_inbox

    def shared_inbox
      inbox_url
    end
  end

  class ImageWithDescription < SimpleDelegator
    attr_reader :description

    def initialize(object, description)
      super(object)

      @description = description
    end
  end

  has_one :endpoints, serializer: EndpointsSerializer

  # disable default account icon
  has_one :icon,  serializer: ActivityPub::ImageSerializer
  has_one :image, serializer: ActivityPub::ImageSerializer, if: :header_exists?

  delegate :suspended?, :instance_actor?, to: :object

  def id
    ActivityPub::TagManager.instance.uri_for(object)
  end

  def webfinger
    object.local_username_and_domain
  end

  def type
    if object.instance_actor?
      'Application'
    elsif object.bot?
      'Service'
    elsif object.group?
      'Group'
    else
      'Person'
    end
  end

  def following
    ActivityPub::TagManager.instance.following_uri_for(object)
  end

  def followers
    ActivityPub::TagManager.instance.followers_uri_for(object)
  end

  def inbox
    ActivityPub::TagManager.instance.inbox_uri_for(object)
  end

  def outbox
    ActivityPub::TagManager.instance.outbox_uri_for(object)
  end

  def featured
    ActivityPub::TagManager.instance.collection_uri_for(object, :featured)
  end

  def featured_tags
    ActivityPub::TagManager.instance.collection_uri_for(object, :tags)
  end

  def endpoints
    object
  end

  def preferred_username
    object.username
  end

  def discoverable
    object.unavailable? ? false : (object.discoverable || false)
  end

  def indexable
    object.unavailable? ? false : (object.indexable || false)
  end

  def name
    object.unavailable? ? object.username : (object.display_name.presence || object.username)
  end

  def summary
    object.unavailable? ? '' : account_bio_format(object)
  end

  def icon
    ImageWithDescription.new(object.avatar, object.avatar_description)
  end

  def image
    ImageWithDescription.new(object.header, object.header_description)
  end

  def public_key
    object
  end

  def suspended
    object.suspended?
  end

  def misskey_followed_message
    object.followed_message
  end

  def cat?
    Setting.cat_enabled &&
      Setting.cat_federation_enabled &&
      !object.unavailable? &&
      object.is_cat?
  end

  def followed_message?
    !object.unavailable? && object.followed_message.present?
  end

  def avatar_decorations_enabled?
    Setting.avatar_decorations_enabled &&
      Setting.avatar_decorations_federation_enabled &&
      !object.unavailable? &&
      !object.avatar_decorations_blocked &&
      object.avatar_decorations.any?
  end

  def misskey_avatar_decorations
    decoration_ids = object.avatar_decorations.filter_map { |d| d['id'] }
    return [] if decoration_ids.empty?

    decorations_by_id = AvatarDecoration.find_many_cached(decoration_ids).index_by(&:id)

    object.avatar_decorations.filter_map do |config|
      decoration = decorations_by_id[config['id']]
      next if decoration.nil?

      {
        id: decoration.id.to_s,
        url: full_asset_url(decoration.image_url),
        staticUrl: full_asset_url(decoration.image_static_url),
        angle: config['angle'] || 0.0,
        flipH: config['flip_h'] || false,
        offsetX: config['offset_x'] || 0.0,
        offsetY: config['offset_y'] || 0.0,
        scale: config['scale'] || 1.0,
        opacity: config['opacity'] || 1.0,
      }
    end
  end

  def url
    object.instance_actor? ? about_more_url(instance_actor: true) : short_account_url(object)
  end

  def avatar_exists?
    !object.unavailable? && object.avatar?
  end

  def header_exists?
    !object.unavailable? && object.header?
  end

  def manually_approves_followers
    object.unavailable? ? false : object.locked
  end

  def virtual_tags
    object.unavailable? ? [] : (object.emojis + object.tags)
  end

  def virtual_attachments
    object.unavailable? ? [] : object.fields
  end

  def moved_to
    ActivityPub::TagManager.instance.uri_for(object.moved_to_account)
  end

  def moved?
    !object.unavailable? && object.moved?
  end

  def also_known_as?
    !object.unavailable? && !object.also_known_as.empty?
  end

  def published
    object.created_at.midnight.iso8601
  end

  def interaction_policy
    uri = begin
      if !object.discoverable?
        ActivityPub::TagManager.instance.uri_for(object)
      elsif object.locked?
        ActivityPub::TagManager.instance.followers_uri_for(object)
      else
        ActivityPub::TagManager::COLLECTIONS[:public]
      end
    end

    {
      canFeature: {
        automaticApproval: [uri],
      },
    }
  end

  def featured_collections
    return nil if instance_actor?

    ap_account_featured_collections_url(object.id)
  end

  class CustomEmojiSerializer < ActivityPub::EmojiSerializer
  end

  class TagSerializer < ActivityPub::Serializer
    context_extensions :hashtag

    include RoutingHelper

    attributes :type, :href, :name

    def type
      'Hashtag'
    end

    def href
      tag_url(object)
    end

    def name
      "##{object.name}"
    end
  end

  class Account::FieldSerializer < ActivityPub::Serializer
    include FormattingHelper

    attributes :type, :name, :value

    def type
      'PropertyValue'
    end

    def value
      account_field_value_format(object)
    end
  end

  class AccountIdentityProofSerializer < ActivityPub::Serializer
    attributes :type, :name, :signature_algorithm, :signature_value

    def type
      'IdentityProof'
    end

    def name
      object.provider_username
    end

    def signature_algorithm
      object.provider
    end

    def signature_value
      object.token
    end
  end
end
