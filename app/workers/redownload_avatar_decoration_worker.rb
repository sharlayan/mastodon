# frozen_string_literal: true

class RedownloadAvatarDecorationWorker
  include Sidekiq::Worker
  include ExponentialBackoff

  sidekiq_options queue: 'pull', retry: 3

  def perform(id)
    decoration = AvatarDecoration.find(id)

    return unless decoration.image_repairable?
    return if decoration.host.present? && AvatarDecorationDomainBlock.blocked?(decoration.host)

    decoration.repair_image!
  rescue ActiveRecord::RecordNotFound
    # Do nothing
  end
end
