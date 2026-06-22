# frozen_string_literal: true

class Api::V1::ReactionMutesController < Api::BaseController
  before_action -> { doorkeeper_authorize! :read, :'read:mutes' }, only: :index
  before_action -> { doorkeeper_authorize! :write, :'write:mutes' }, except: :index
  before_action :require_user!

  def index
    @mutes = current_account.reaction_mutes.includes(:target_account).order(id: :desc)
    render json: @mutes, each_serializer: REST::ReactionMuteSerializer
  end

  def create
    if params[:account_id].present?
      target = Account.find(params[:account_id])
      mute = current_account.reaction_mutes.find_or_create_by!(target_account: target)
    elsif params[:acct].present?
      target = ResolveAccountService.new.call(params[:acct].to_s.strip.delete_prefix('@'))
      return render json: { error: 'Account not found' }, status: 404 if target.nil?

      mute = current_account.reaction_mutes.find_or_create_by!(target_account: target)
    elsif params[:domain].present?
      domain = TagManager.instance.normalize_domain(params[:domain])
      return render json: { error: 'Invalid domain' }, status: 422 if domain.blank?

      mute = current_account.reaction_mutes.find_or_create_by!(target_domain: domain)
    else
      return render json: { error: 'Must provide account_id or domain' }, status: 422
    end

    render json: mute, serializer: REST::ReactionMuteSerializer
  end

  def destroy
    mute = current_account.reaction_mutes.find(params[:id])
    mute.destroy!
    render_empty
  end
end
