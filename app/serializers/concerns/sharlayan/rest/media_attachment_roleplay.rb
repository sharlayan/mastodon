# frozen_string_literal: true

module Sharlayan::REST::MediaAttachmentRoleplay
  def url
    return super if object.not_processed?
    return medium_url(object.id) if rp_hidden_media?

    super
  end

  def preview_url
    return medium_url(object.id) if rp_hidden_media?

    super
  end

  private

  def rp_hidden_media?
    return false unless instance_options[:rp_admin] || Sharlayan::SoftHide.enabled?

    object.status_id.present? && RpHiddenStatus.exists?(status_id: object.status_id)
  end
end
