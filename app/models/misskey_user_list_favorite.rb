# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_user_list_favorites
#
#  id         :bigint(8)        not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint(8)        not null
#  list_id    :bigint(8)        not null
#
class MisskeyUserListFavorite < ApplicationRecord
  belongs_to :account
  belongs_to :list
end
