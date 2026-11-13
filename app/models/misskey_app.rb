# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_apps
#
#  id                   :bigint(8)        not null, primary key
#  callback_url         :string
#  description          :text             default(""), not null
#  permission           :string           default([]), not null, is an Array
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  oauth_application_id :bigint(8)        not null
#
class MisskeyApp < ApplicationRecord
  belongs_to :application, class_name: 'Doorkeeper::Application', foreign_key: :oauth_application_id, inverse_of: :misskey_app

  validates :oauth_application_id, uniqueness: true
end
