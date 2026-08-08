# frozen_string_literal: true

class MigrateHideOnlineStatusToShowOnlineStatus < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  class MigrationUser < ApplicationRecord
    self.table_name = 'users'
  end

  OLD_KEY = 'hide_online_status'
  NEW_KEY = 'show_online_status'

  def up
    migrate_setting(OLD_KEY, NEW_KEY)
  end

  def down
    migrate_setting(NEW_KEY, OLD_KEY)
  end

  private

  def migrate_setting(source_key, target_key)
    MigrationUser.where('settings LIKE ?', "%#{source_key}%").find_each do |user|
      data = JSON.parse(user.settings)
      next unless data.key?(source_key)

      source_value = data.delete(source_key)
      data[target_key] = !ActiveModel::Type::Boolean.new.cast(source_value) unless data.key?(target_key)
      user.update_column(:settings, JSON.generate(data))
    rescue JSON::ParserError
      next
    end
  end
end
