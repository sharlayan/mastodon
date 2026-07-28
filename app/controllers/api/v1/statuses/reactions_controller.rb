# frozen_string_literal: true

class Api::V1::Statuses::ReactionsController < Api::V1::Statuses::BaseController
  include Api::AccountRateLimit

  before_action -> { doorkeeper_authorize! :write, :'write:favourites' }
  before_action :require_user!
  before_action :enforce_reaction_rate_limit!
  skip_before_action :set_status, only: [:destroy]

  def create
    return not_found unless Setting.reactions_enabled

    ReactService.new.call(current_account, @status, params[:id])
    render json: @status, serializer: REST::StatusSerializer
  rescue ActiveRecord::RecordNotFound, Mastodon::NotPermittedError
    not_found
  end

  def destroy
    reaction = find_reaction

    if reaction
      @status = reaction.status
      count = [@status.reactions_count - 1, 0].max
      UnreactWorker.perform_async(current_account.id, @status.id, params[:id])
    else
      @status = Status.find(params[:status_id])
      count = @status.reactions_count
      authorize @status, :show?
    end

    relationships = StatusRelationshipsPresenter.new([@status], current_account.id, attributes_map: { @status.id => { reactions_count: count } })
    render json: @status, serializer: REST::StatusSerializer, relationships: relationships
  rescue ActiveRecord::RecordNotFound, Mastodon::NotPermittedError
    not_found
  end

  private

  def enforce_reaction_rate_limit!
    enforce_account_rate_limit!(:status_reactions)
  end

  def find_reaction
    name, domain = params[:id].to_s.split('@')
    custom_emoji = CustomEmoji.find_by(shortcode: name, domain: domain)
    current_account.status_reactions.find_by(status_id: params[:status_id], name: name, custom_emoji: custom_emoji)
  end
end
