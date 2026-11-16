# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_system_webhooks
#
#  id         :bigint(8)        not null, primary key
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  webhook_id :bigint(8)        not null
#
class MisskeySystemWebhook < ApplicationRecord
  belongs_to :webhook

  validates :name, presence: true, length: { maximum: 255 }
  validates :webhook_id, uniqueness: true
end
