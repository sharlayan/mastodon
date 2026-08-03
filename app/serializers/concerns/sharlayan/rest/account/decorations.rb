# frozen_string_literal: true

module Sharlayan::REST::Account::Decorations
  extend ActiveSupport::Concern

  included do
    attribute :avatar_decorations, if: :decorations_enabled?
  end

  def decorations_enabled?
    Setting.avatar_decorations_enabled && !object.avatar_decorations_blocked
  end

  def avatar_decorations
    return [] if object.unavailable? || object.avatar_decorations.blank?
    return [] if object.local? && Setting.avatar_decorations_local_only_view

    decoration_ids = object.avatar_decorations.filter_map { |decoration| decoration['id'] }
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
