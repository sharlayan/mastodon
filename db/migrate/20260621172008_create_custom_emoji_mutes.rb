# frozen_string_literal: true

class CreateCustomEmojiMutes < ActiveRecord::Migration[8.1]
  def change
    create_table :custom_emoji_mutes do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string     :prefix,  null: false, default: ''
      t.string     :domain,  null: false, default: ''

      t.timestamps null: false
    end

    add_index :custom_emoji_mutes, %i(account_id prefix domain), unique: true,
                                                                 name: 'index_custom_emoji_mutes_on_account_prefix_domain'
  end
end
