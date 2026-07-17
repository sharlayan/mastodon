# frozen_string_literal: true

# == Schema Information
#
# Table name: page_reports
#
#  id         :bigint(8)        not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  page_id    :bigint(8)        not null
#  report_id  :bigint(8)        not null
#
class PageReport < ApplicationRecord
  belongs_to :page
  belongs_to :report
end
