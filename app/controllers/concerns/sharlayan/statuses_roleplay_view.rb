# frozen_string_literal: true

module Sharlayan::StatusesRoleplayView
  private

  def set_status
    return super unless request.format.html? && roleplay_owner_viewer?

    @status = Status.with_rp_hidden.where(account: @account).find(params[:id])
    authorize @status, :show?
  rescue ActiveRecord::RecordNotFound, Mastodon::NotPermittedError
    not_found
  end

  def roleplay_owner_viewer?
    return false unless Sharlayan::SoftHide.enabled?

    role = current_user&.role
    role.present? && !role.everyone? && role.position == UserRole.assignable.maximum(:position)
  end
end
