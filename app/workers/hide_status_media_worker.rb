# frozen_string_literal: true

class HideStatusMediaWorker
  include Sidekiq::Worker

  def perform(status_id)
    status = Status.with_rp_hidden.find(status_id)
    hidden = status.rp_hidden_status
    return unless hidden

    UpdateMediaAttachmentsPermissionsService.new.call(status.media_attachments.reorder(nil), :private)
    hidden.update!(media_moved: true)
  rescue ActiveRecord::RecordNotFound
    true
  end
end
