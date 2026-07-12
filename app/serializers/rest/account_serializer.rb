# frozen_string_literal: true

class REST::AccountSerializer < ActiveModel::Serializer
  include RoutingHelper
  include FormattingHelper

  # Please update `app/javascript/mastodon/api_types/accounts.ts` when making changes to the attributes

  attributes :id, :username, :acct, :display_name, :locked, :bot, :discoverable, :indexable, :group, :created_at,
             :note, :url, :uri, :avatar, :avatar_static, :avatar_description, :header, :header_static, :header_description,
             :followers_count, :following_count, :statuses_count, :last_status_at, :hide_collections,
             :show_media, :show_media_replies, :show_featured, :followed_message

  has_one :moved_to_account, key: :moved, serializer: REST::AccountSerializer, if: :moved_and_not_nested?

  has_many :emojis, serializer: REST::CustomEmojiSerializer

  attribute :suspended, if: :suspended?
  attribute :silenced, key: :limited, if: :silenced?
  attribute :noindex, if: :local?

  attribute :memorial, if: :memorial?

  attribute :feature_approval
  attribute :email_subscriptions, if: -> { Rails.application.config.x.email_subscriptions && Setting.email_subscriptions }

  attribute :avatar_decorations, if: :decorations_enabled?

  attribute :mfm, if: :mfm?

  attribute :server_features, if: :instance_metadata_enabled?
  attribute :software, if: :instance_metadata_enabled?

  attribute :online_status

  class AccountDecorator < SimpleDelegator
    def self.model_name
      Account.model_name
    end

    def moved?
      false
    end
  end

  class RoleSerializer < ActiveModel::Serializer
    attributes :id, :name, :color

    def id
      object.id.to_s
    end
  end

  has_many :roles, serializer: RoleSerializer, if: :local?

  class FieldSerializer < ActiveModel::Serializer
    include FormattingHelper

    attributes :name, :value, :verified_at

    def value
      account_field_value_format(object)
    end
  end

  has_many :fields

  def id
    object.id.to_s
  end

  def acct
    object.pretty_acct
  end

  def note
    object.unavailable? ? '' : account_bio_format(object)
  end

  def url
    ActivityPub::TagManager.instance.url_for(object) || ActivityPub::TagManager.instance.uri_for(object)
  end

  def uri
    ActivityPub::TagManager.instance.uri_for(object)
  end

  def avatar
    full_asset_url(object.unavailable? ? object.avatar.default_url : object.avatar_original_url)
  end

  def avatar_static
    full_asset_url(object.unavailable? ? object.avatar.default_url : object.avatar_static_url)
  end

  def avatar_description
    object.unavailable? ? '' : object.avatar_description
  end

  def header
    full_asset_url(object.unavailable? ? object.header.default_url : object.header_original_url)
  end

  def header_static
    full_asset_url(object.unavailable? ? object.header.default_url : object.header_static_url)
  end

  def header_description
    object.unavailable? ? '' : object.header_description
  end

  def created_at
    object.created_at.midnight.as_json
  end

  def last_status_at
    object.last_status_at&.to_date&.iso8601
  end

  def followers_count
    Setting.hide_followers_count || object.user&.setting_hide_followers_count ? -1 : object.followers_count
  end

  def display_name
    object.unavailable? ? '' : object.display_name
  end

  def locked
    object.unavailable? ? false : object.locked
  end

  def bot
    object.unavailable? ? false : object.bot
  end

  def discoverable
    object.unavailable? ? false : object.discoverable
  end

  def indexable
    object.unavailable? ? false : object.indexable
  end

  def moved_to_account
    object.unavailable? ? nil : AccountDecorator.new(object.moved_to_account)
  end

  def emojis
    object.unavailable? ? [] : object.emojis
  end

  def fields
    object.unavailable? ? [] : object.fields
  end

  def suspended
    object.unavailable?
  end

  def silenced
    object.silenced?
  end

  def memorial
    object.memorial?
  end

  def roles
    if object.unavailable? || object.user.nil?
      []
    else
      [object.user.role].compact.filter(&:highlighted?)
    end
  end

  def noindex
    object.user_prefers_noindex?
  end

  delegate :suspended?, :silenced?, :local?, :memorial?, to: :object

  def moved_and_not_nested?
    object.moved?
  end

  def feature_approval
    {
      automatic: object.feature_policy_as_keys(:automatic),
      manual: object.feature_policy_as_keys(:manual),
      current_user: object.feature_policy_for_account(current_user&.account),
    }
  end

  def email_subscriptions
    object.user_can?(:manage_email_subscriptions) && object.user_email_subscriptions_enabled?
  end

  def decorations_enabled?
    Setting.avatar_decorations_enabled && !object.avatar_decorations_blocked
  end

  def online_status
    return 'unknown' unless Setting.online_status_enabled
    return 'unknown' if current_user.nil? || object.unavailable? || object.user.nil?

    object.user.online_status
  end

  def mfm
    true
  end

  def mfm?
    return false if object.unavailable?
    return false unless object.mfm?

    object.local? || instance_supports_mfm?
  end

  def instance_supports_mfm?
    return false unless Setting.instance_metadata_enabled
    return false if object.domain.blank?

    InstanceMetadata.cached_by_domain(object.domain)&.misskey_based? || false
  end

  def instance_metadata_enabled?
    Setting.instance_metadata_enabled
  end

  def server_features
    return InstanceMetadata.local_server_features if object.local?
    return InstanceMetadata.blank_server_features if object.domain.blank?

    InstanceMetadata.cached_by_domain(object.domain)&.server_features || InstanceMetadata.blank_server_features
  end

  def software
    return 'mastodon' if object.local?
    return nil if object.domain.blank?

    InstanceMetadata.cached_by_domain(object.domain)&.software
  end

  def avatar_decorations
    return [] if object.unavailable? || object.avatar_decorations.blank?

    decoration_ids = object.avatar_decorations.filter_map { |d| d['id'] }
    return [] if decoration_ids.empty?

    decorations_by_id = AvatarDecoration.find_many_cached(decoration_ids).index_by(&:id)
    blocked_domains = AvatarDecorationDomainBlock.blocked_domains_cached

    object.avatar_decorations.filter_map do |config|
      decoration = decorations_by_id[config['id']]
      next if decoration.nil?
      next if decoration.host.present? && blocked_domains.include?(decoration.host)

      {
        id: decoration.id.to_s,
        url: decoration.image_url,
        static_url: decoration.image_static_url,
        angle: config['angle'] || 0.0,
        flip_h: config['flip_h'] || false,
        offset_x: config['offset_x'] || 0.0,
        offset_y: config['offset_y'] || 0.0,
        scale: config['scale'] || 1.0,
        opacity: config['opacity'] || 1.0,
      }
    end
  end
end
