# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_registry_items
#
#  id         :bigint(8)        not null, primary key
#  domain     :string
#  key        :string           default(""), not null
#  scope      :string           default([]), not null, is an Array
#  value      :jsonb
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint(8)        not null
#
class MisskeyRegistryItem < ApplicationRecord
  belongs_to :account

  validates :key, presence: true, length: { maximum: 1024 }
end
