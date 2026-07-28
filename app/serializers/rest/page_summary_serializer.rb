# frozen_string_literal: true

class REST::PageSummarySerializer < REST::PageSerializer
  def content
    []
  end

  def attached_media
    []
  end

  def current_user?
    false
  end
end
