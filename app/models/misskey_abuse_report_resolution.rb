# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_abuse_report_resolutions
#
#  id          :bigint(8)        not null, primary key
#  resolved_as :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  report_id   :bigint(8)        not null
#
class MisskeyAbuseReportResolution < ApplicationRecord
  RESOLUTIONS = %w(accept reject).freeze

  belongs_to :report

  validates :report_id, uniqueness: true
  validates :resolved_as, inclusion: { in: RESOLUTIONS }

  def self.record!(report, resolved_as)
    if resolved_as.nil?
      where(report: report).delete_all
    else
      find_or_initialize_by(report: report).update!(resolved_as: resolved_as)
    end
  end
end
