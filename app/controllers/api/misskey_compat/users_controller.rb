# frozen_string_literal: true

class Api::MisskeyCompat::UsersController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false

  def show
    username = params[:username].to_s.strip
    return render json: { error: 'Missing username' }, status: 400 if username.blank?

    @account = Account.local.find_by(username: username)
    return render json: { error: 'Not Found' }, status: 404 if @account.nil?

    begin
      RateLimiter.new(@account, family: :misskey_users_show).record!
    rescue Mastodon::RateLimitExceededError
      return render json: { error: I18n.t('errors.429') }, status: 429
    end

    avatar_decorations = []

    if Setting.avatar_decorations_enabled && Setting.avatar_decorations_federation_enabled &&
       !@account.avatar_decorations_blocked && @account.avatar_decorations.any?

      decoration_ids = @account.avatar_decorations.filter_map { |d| d['id'] }
      decorations_by_id = AvatarDecoration.where(id: decoration_ids).index_by(&:id)

      avatar_decorations = @account.avatar_decorations.filter_map do |config|
        decoration = decorations_by_id[config['id']]
        next if decoration.nil?

        {
          id: decoration.id.to_s,
          url: decoration.image_url,
          angle: config['angle'] || 0.0,
          flipH: config['flip_h'] || false,
          offsetX: config['offset_x'] || 0.0,
          offsetY: config['offset_y'] || 0.0,
          scale: config['scale'] || 1.0,
          opacity: config['opacity'] || 1.0,
        }
      end
    end

    render json: {
      id: @account.id.to_s,
      username: @account.username,
      name: @account.display_name,
      avatarUrl: @account.avatar_url,
      avatarDecorations: avatar_decorations,
    }
  end
end
