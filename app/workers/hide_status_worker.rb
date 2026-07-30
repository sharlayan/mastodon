# frozen_string_literal: true

class HideStatusWorker
  include Sidekiq::Worker

  def perform(status_id, options = {})
    return unless Sharlayan::SoftHide.enabled?

    HideStatusService.new.call(Status.with_rp_hidden.find(status_id), **options.symbolize_keys)
  rescue ActiveRecord::RecordNotFound
    true
  end
end
