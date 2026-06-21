# frozen_string_literal: true

class Api::V1::CustomEmojiMutesController < Api::BaseController
  before_action -> { doorkeeper_authorize! :read, :'read:mutes' }, only: :index
  before_action -> { doorkeeper_authorize! :write, :'write:mutes' }, except: :index
  before_action :require_user!

  def index
    @mutes = current_account.custom_emoji_mutes.order(id: :desc)
    render json: @mutes, each_serializer: REST::CustomEmojiMuteSerializer
  end

  def create
    prefix = params[:prefix].to_s.strip
    return render json: { error: 'Must provide prefix' }, status: 422 if prefix.blank?

    domain = params[:domain].to_s.strip
    domain = TagManager.instance.normalize_domain(domain) if domain.present?

    mute = current_account.custom_emoji_mutes.find_or_create_by!(prefix: prefix, domain: domain.to_s)

    render json: mute, serializer: REST::CustomEmojiMuteSerializer
  end

  def destroy
    mute = current_account.custom_emoji_mutes.find(params[:id])
    mute.destroy!
    render_empty
  end
end
