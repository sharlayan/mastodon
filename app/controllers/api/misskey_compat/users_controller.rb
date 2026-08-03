# frozen_string_literal: true

class Api::MisskeyCompat::UsersController < Api::MisskeyCompat::BaseController
  def show
    @account = find_account
    return render_error('No such user', 'NO_SUCH_USER', 404) if @account.nil?
    return if rate_limited?(:misskey_users_show)

    me_user = current_user if current_user && current_user.account_id == @account.id
    render json: MisskeyCompat::UserSerializer.serialize(@account, detailed: true, viewer: current_account, me_user: me_user).merge(avatarDecorations: federated_avatar_decorations)
  end

  private

  def federated_avatar_decorations
    return [] unless Setting.avatar_decorations_federation_enabled

    MisskeyCompat::UserSerializer.avatar_decorations_for(@account)
  end

  def find_account
    scope = Account.without_requested_deletion

    if params[:userId].present?
      scope.find_by(id: params[:userId])
    else
      username = params[:username].to_s.strip
      return nil if username.blank?

      domain = params[:host].to_s.strip.presence
      domain.nil? ? scope.local.find_by(username: username) : scope.find_by(username: username, domain: domain)
    end
  end
end
