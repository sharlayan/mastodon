# frozen_string_literal: true

class MoveEmojiReactionSettings < ActiveRecord::Migration[6.1]
  class User < ApplicationRecord; end

  MAPPING = {
    setting_visible_reactions: 'visible_reactions',
  }.freeze

  class LegacySetting < ApplicationRecord
    self.table_name = 'settings'

    def var
      self[:var]&.to_sym
    end

    def value
      YAML.safe_load(self[:value], permitted_classes: [ActiveSupport::HashWithIndifferentAccess]) if self[:value].present?
    end
  end

  def up
    return unless ActiveRecord::Base.connection.table_exists?('settings')

    return unless ActiveRecord::Base.connection.column_exists?('settings', 'thing_type')
    return unless ActiveRecord::Base.connection.column_exists?('settings', 'thing_id')

    User.find_in_batches do |users|
      previous_settings_for_batch = LegacySetting.where(thing_type: 'User', thing_id: users.map(&:id)).group_by(&:thing_id)

      users.each do |user|
        previous_settings = previous_settings_for_batch[user.id]&.index_by(&:var) || {}
        user_settings = JSON.parse(user.settings || '{}')
        user_settings.delete('theme')

        MAPPING.each do |legacy_key, new_key|
          value = previous_settings[legacy_key]&.value

          next if value.blank?

          if value.is_a?(Hash)
            value.each do |nested_key, nested_value|
              user_settings[MAPPING[legacy_key][nested_key.to_sym]] = nested_value
            end
          else
            user_settings[new_key] = value
          end
        end

        user.update_column('settings', JSON.generate(user_settings))
      end
    end
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.info "Skipping MoveEmojiReactionSettings migration: #{e.message}"
  end

  def down; end
end
