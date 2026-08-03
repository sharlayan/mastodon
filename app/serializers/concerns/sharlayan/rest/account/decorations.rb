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
    return [] if object.unavailable?

    AvatarDecoration.visible_configs_for(object).map do |config, decoration|
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
