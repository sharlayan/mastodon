# frozen_string_literal: true

class AddFromMisskeyToQuotes < ActiveRecord::Migration[8.0]
  def change
    add_column :quotes, :from_misskey, :boolean, null: false, default: false
  end
end
