# frozen_string_literal: true

class PageReport < ApplicationRecord
  belongs_to :page
  belongs_to :report
end
