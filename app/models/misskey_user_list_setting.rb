# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_user_list_settings
#
#  id         :bigint(8)        not null, primary key
#  is_public  :boolean          default(FALSE), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  list_id    :bigint(8)        not null
#
class MisskeyUserListSetting < ApplicationRecord
  belongs_to :list

  scope :public_lists, -> { where(is_public: true) }

  def self.public_list_ids(list_ids)
    public_lists.where(list_id: list_ids).pluck(:list_id).to_set
  end

  def self.update_public!(list, value)
    find_or_initialize_by(list: list).update!(is_public: value)
  end
end
