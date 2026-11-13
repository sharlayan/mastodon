# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_abuse_report_recipients
#
#  id              :bigint(8)        not null, primary key
#  active          :boolean          default(TRUE), not null
#  delivery_method :string           not null
#  name            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint(8)
#  webhook_id      :bigint(8)
#
class MisskeyAbuseReportRecipient < ApplicationRecord
  METHODS = %w(email webhook).freeze

  belongs_to :account, optional: true
  belongs_to :webhook, optional: true

  scope :active, -> { where(active: true) }

  validates :name, presence: true, length: { maximum: 255 }
  validates :delivery_method, inclusion: { in: METHODS }
  validates :account, presence: true, if: -> { delivery_method == 'email' }
  validates :webhook, presence: true, if: -> { delivery_method == 'webhook' }

  def self.notify!(report)
    active.where(delivery_method: 'email').includes(account: :user).find_each.select(&:email_deliverable?).uniq(&:account_id).each do |recipient|
      AdminMailer.with(recipient: recipient.account).new_report(report).deliver_later
    end
  end

  def email_deliverable?
    user = account&.user
    delivery_method == 'email' && user.present? && user.functional? && user.confirmed? && user.can?(:manage_reports) && !user.allows_report_emails?
  end
end
