# frozen_string_literal: true

class Api::MisskeyCompat::UsersController < Api::MisskeyCompat::BaseController
  def show
    if params.key?(:userIds)
      return if rate_limited?(:misskey_users_show)

      ids = params[:userIds]
      return render_invalid_param('#/userIds', 'must be an array of unique strings') unless ids.is_a?(Array) && ids.all?(String) && ids.uniq.size == ids.size

      accounts = Account.without_requested_deletion.where(id: ids).index_by { |account| account.id.to_s }
      return render json: ids.filter_map { |id| serialize_account(accounts[id]) if accounts.key?(id) }
    end

    @account = find_account
    return render_error('No such user', 'NO_SUCH_USER', 404) if @account.nil?
    return if rate_limited?(:misskey_users_show)

    render json: serialize_account(@account)
  end

  private

  def serialize_account(account)
    me_user = current_user if current_user && current_user.account_id == account.id
    MisskeyCompat::UserSerializer.serialize(account, detailed: true, viewer: current_account, me_user: me_user).merge(avatarDecorations: federated_avatar_decorations(account))
  end

  def federated_avatar_decorations(account)
    return [] unless Setting.avatar_decorations_federation_enabled

    MisskeyCompat::UserSerializer.avatar_decorations_for(account)
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
