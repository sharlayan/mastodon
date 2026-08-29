# frozen_string_literal: true

module Sharlayan::Api::StatusesRoleplayDeletion
  def show
    return super unless roleplay_owner_deletion? && @status.rp_hidden?

    @status = preload_collection([@status], Status).first
    render json: @status, serializer: REST::StatusSerializer, rp_admin: true
  end

  def destroy
    return super unless roleplay_soft_hide_deletion?

    @status = roleplay_deletion_scope.find(params[:id])
    authorize @status, :destroy?

    json = render_to_body json: @status, serializer: REST::StatusSerializer, source_requested: true

    if @status.rp_hidden?
      purge_roleplay_hidden_status
    else
      hide_roleplay_status
    end

    render json: json
  end

  private

  def set_status
    return super unless roleplay_owner_deletion?

    @status = Status.with_rp_hidden.find(params[:id])
    authorize @status, :show?
  rescue ActiveRecord::RecordNotFound, Mastodon::NotPermittedError
    not_found
  end

  def roleplay_soft_hide_deletion?
    Sharlayan::SoftHide.enabled?
  end

  def roleplay_deletion_scope
    roleplay_owner_deletion? ? Status.with_rp_hidden : Status.where(account: current_account)
  end

  def roleplay_owner_deletion?
    return false unless roleplay_soft_hide_deletion?
    return false unless current_user

    role = current_user.role
    !role.everyone? && role.position == UserRole.assignable.maximum(:position)
  end

  def hide_roleplay_status
    @status.account.statuses_count -= 1

    HideStatusWorker.perform_async(@status.id, { 'hidden_by_account_id' => current_account.id })
  end

  def purge_roleplay_hidden_status
    @status.discard_with_reblogs
    StatusPin.find_by(status: @status)&.destroy

    PurgeStatusWorker.perform_async(@status.id)
  end
end
