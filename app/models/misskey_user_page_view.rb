# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_user_page_views
#
#  id         :bigint(8)        not null, primary key
#  bucket_at  :datetime         not null
#  viewer_key :string           not null
#  views      :integer          default(0), not null
#  visitor    :boolean          default(FALSE), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint(8)        not null
#
class MisskeyUserPageView < ApplicationRecord
  belongs_to :account

  def self.record!(account, viewer: nil, ip: nil)
    return unless account&.local?

    if viewer
      return if viewer.id == account.id

      increment!(account, false, viewer.id.to_s)
    elsif ip.present?
      increment!(account, true, visitor_key(ip))
    end
  end

  def self.increment!(account, visitor, viewer_key)
    now = Time.now.utc
    upsert(
      { account_id: account.id, bucket_at: now.beginning_of_hour, visitor: visitor, viewer_key: viewer_key, views: 1, created_at: now, updated_at: now },
      unique_by: :index_misskey_user_page_views_on_viewer_bucket,
      on_duplicate: Arel.sql('views = misskey_user_page_views.views + 1, updated_at = excluded.updated_at')
    )
  end

  def self.visitor_key(ip)
    OpenSSL::HMAC.hexdigest('SHA256', Rails.application.key_generator.generate_key('misskey_compat_user_page_views'), ip.to_s)
  end

  private_class_method :increment!, :visitor_key
end
