# frozen_string_literal: true

class Api::MisskeyCompat::Admin::PromoController < Api::MisskeyCompat::Admin::ServerBaseController
  misskey_admin_endpoint :create, kind: 'write:admin:promo', permission: :manage_taxonomies

  def create
    return unless require_keys!(:noteId, :expiresAt) && require_integer_param!(:expiresAt, required: true)

    status = Status.find_by(id: params[:noteId])
    return render_error('No such note', 'NO_SUCH_NOTE', 404, id: 'ee449fbe-af2a-453b-9cae-cf2fe7c895fc') if status.nil?
    return render_error('The note has already promoted', 'ALREADY_PROMOTED', 400, id: 'ae427aa2-7a41-484f-a18c-2c1104051604') if MisskeyPromoNote.exists?(status_id: status.id)

    MisskeyPromoNote.create!(status: status, account_id: status.account_id, expires_at: Time.zone.at(params[:expiresAt] / 1000.0))
    head 204
  end
end
