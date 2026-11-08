# frozen_string_literal: true

class HideStatusWorker
  include Sidekiq::Worker

  def perform(status_id, options = {})
    status = Status.with_rp_hidden.find(status_id)

    if Sharlayan::SoftHide.enabled?
      HideStatusService.new.call(status, **options.symbolize_keys)
    elsif !RpHiddenStatus.exists?(status_id: status.id)
      status.discard_with_reblogs
      StatusPin.find_by(status: status)&.destroy
      RemoveStatusService.new.call(status)
    end
  rescue ActiveRecord::RecordNotFound
    true
  end
end
