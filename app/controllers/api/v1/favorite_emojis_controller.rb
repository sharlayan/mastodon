# frozen_string_literal: true

class Api::V1::FavoriteEmojisController < Api::BaseController
  before_action -> { doorkeeper_authorize! :read, :'read:accounts' }, only: :index
  before_action -> { doorkeeper_authorize! :write, :'write:accounts' }, except: :index
  before_action :require_user!
  before_action :set_favorite_emoji, only: :destroy

  def index
    @favorite_emojis = current_account.favorite_emojis.ordered
    render json: @favorite_emojis, each_serializer: REST::FavoriteEmojiSerializer
  end

  MAX_FAVORITE_EMOJIS = 200

  def create
    return render json: { error: 'Only custom emojis can be favorited' }, status: 422 if favorite_emoji_params[:emoji_type] == 'unicode'

    name = favorite_emoji_params[:name].to_s
    return render json: { error: 'Invalid emoji shortcode' }, status: 422 unless name.match?(/\A\w{2,30}(@[\w.-]+\.[a-z]{2,})?\z/i)

    shortcode, domain = name.split('@', 2)
    return render json: { error: 'Unknown custom emoji' }, status: 422 unless CustomEmoji.exists?(shortcode: shortcode, domain: domain, disabled: false)

    return render json: { error: 'Too many favorites' }, status: 422 if current_account.favorite_emojis.count >= MAX_FAVORITE_EMOJIS

    position = current_account.favorite_emojis.count
    @favorite_emoji = current_account.favorite_emojis.create!(favorite_emoji_params.merge(position: position))
    render json: @favorite_emoji, serializer: REST::FavoriteEmojiSerializer
  rescue ActiveRecord::RecordNotUnique
    render json: { error: 'Already favorited' }, status: 422
  end

  def destroy
    @favorite_emoji.destroy!
    render_empty
  end

  private

  def set_favorite_emoji
    @favorite_emoji = current_account.favorite_emojis.find_by!(name: params[:name])
  end

  def favorite_emoji_params
    params.permit(:name, :emoji_type)
  end
end
