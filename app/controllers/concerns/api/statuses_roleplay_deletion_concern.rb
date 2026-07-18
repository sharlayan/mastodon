# frozen_string_literal: true

module Api::StatusesRoleplayDeletionConcern
  extend ActiveSupport::Concern

  included do
    include RoleplayModeHelper
  end

  private

  def roleplay_soft_hide_deletion?
    roleplay_mode? && Setting.soft_hide_deletion
  end

  def destroy_with_roleplay_soft_hide
    @status = if owner_soft_hide_deletion?
                Status.with_rp_hidden.find(params[:id])
              else
                Status.where(account: current_account).find(params[:id])
              end
    authorize @status, :destroy?

    json = render_to_body json: @status, serializer: REST::StatusSerializer, source_requested: true

    if @status.rp_hidden?
      @status.discard_with_reblogs
      StatusPin.find_by(status: @status)&.destroy
      PurgeStatusWorker.perform_async(@status.id)
    else
      @status.account.statuses_count -= 1
      HideStatusWorker.perform_async(@status.id, { 'hidden_by_account_id' => current_account.id })
    end

    render json: json
  end

  def owner_soft_hide_deletion?
    return false unless roleplay_soft_hide_deletion?

    role = current_user.role
    !role.everyone? && role.position == UserRole.assignable.maximum(:position)
  end
end
