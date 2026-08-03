# frozen_string_literal: true

class Api::MisskeyCompat::UsersController < Api::MisskeyCompat::BaseController
  def show
    @account = find_account
    return render_error('No such user', 'NO_SUCH_USER', 404) if @account.nil?
    return if rate_limited?(:misskey_users_show)

    avatar_decorations = []

    if Setting.avatar_decorations_enabled && Setting.avatar_decorations_federation_enabled &&
       !@account.avatar_decorations_blocked && @account.avatar_decorations.any?

      decoration_ids = @account.avatar_decorations.filter_map { |d| d['id'] }
      decorations_by_id = AvatarDecoration.where(id: decoration_ids).index_by(&:id)

      avatar_decorations = @account.avatar_decorations.filter_map do |config|
        decoration = decorations_by_id[config['id']]
        next if decoration.nil?

        {
          id: MisskeyCompat::MiId.encode(decoration.id),
          url: full_asset_url(decoration.image_url),
          angle: config['angle'] || 0.0,
          flipH: config['flip_h'] || false,
          offsetX: config['offset_x'] || 0.0,
          offsetY: config['offset_y'] || 0.0,
          scale: config['scale'] || 1.0,
          opacity: config['opacity'] || 1.0,
        }
      end
    end

    me_user = current_user if current_user && current_user.account_id == @account.id
    render json: MisskeyCompat::UserSerializer.serialize(@account, detailed: true, viewer: current_account, me_user: me_user).merge(avatarDecorations: avatar_decorations)
  end

  private

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
