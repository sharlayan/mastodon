# frozen_string_literal: true

class MigrateAvatarDecorationForceRoundToShape < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  class MigrationUser < ApplicationRecord
    self.table_name = 'users'
  end

  OLD_KEY = 'avatar_decorations.force_round'
  NEW_KEY = 'avatar_decorations.shape'

  def up
    MigrationUser.where('settings LIKE ?', "%#{OLD_KEY}%").find_each do |user|
      raw = user.settings
      next if raw.blank?

      data = begin
        JSON.parse(raw)
      rescue JSON::ParserError
        next
      end

      next unless data.key?(OLD_KEY)

      was_round = ActiveModel::Type::Boolean.new.cast(data.delete(OLD_KEY))
      data[NEW_KEY] = 'round' if was_round && data[NEW_KEY].blank?

      user.update_column(:settings, JSON.generate(data))
    end
  end

  def down
    MigrationUser.where('settings LIKE ?', "%#{NEW_KEY}%").find_each do |user|
      raw = user.settings
      next if raw.blank?

      data = begin
        JSON.parse(raw)
      rescue JSON::ParserError
        next
      end

      next unless data.key?(NEW_KEY)

      shape = data.delete(NEW_KEY)
      data[OLD_KEY] = true if shape == 'round'

      user.update_column(:settings, JSON.generate(data))
    end
  end
end
