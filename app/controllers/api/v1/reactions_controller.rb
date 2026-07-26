# frozen_string_literal: true

class Api::V1::ReactionsController < Api::BaseController
  include RoutingHelper

  before_action -> { doorkeeper_authorize! :read, :'read:favourites' }
  before_action :require_user!
  after_action :insert_pagination_headers, only: :index

  def index
    @statuses = load_statuses
    render json: @statuses, each_serializer: REST::StatusSerializer, relationships: StatusRelationshipsPresenter.new(@statuses, current_user&.account_id)
  end

  def summary
    @summary = build_reaction_summary
    render json: @summary
  end

  private

  def load_statuses
    preloaded_reactions
  end

  def preloaded_reactions
    preload_collection(results.map(&:status), Status)
  end

  def results
    @results ||= account_reactions.joins(:status).eager_load(:status).to_a_paginated_by_id(
      limit_param(DEFAULT_STATUSES_LIMIT),
      params_slice(:max_id, :since_id, :min_id)
    )
  end

  def account_reactions
    scope = current_account.status_reactions
    scope = scope.where(name: params[:name]) if params[:name].present?
    scope
  end

  def build_reaction_summary
    grouped = current_account.status_reactions
      .group(:name, :custom_emoji_id)
      .order(Arel.sql('COUNT(*) DESC'))
      .count

    emoji_ids = grouped.keys.filter_map { |(_name, emoji_id)| emoji_id }
    emojis = CustomEmoji.where(id: emoji_ids).index_by(&:id)

    grouped.map do |(name, custom_emoji_id), count|
      custom_emoji = emojis[custom_emoji_id] if custom_emoji_id.present?
      unknown = custom_emoji_id.present? && custom_emoji.nil?

      entry = { name: name, count: count, unknown: unknown }

      if custom_emoji.present?
        entry[:url] = full_asset_url(custom_emoji.image.url)
        entry[:static_url] = full_asset_url(custom_emoji.image.url(:static))
        entry[:domain] = custom_emoji.domain || ''
        entry[:is_sensitive] = custom_emoji.is_sensitive
      end

      entry
    end
  end

  def next_path
    api_v1_reactions_url pagination_params(max_id: pagination_max_id) if records_continue?
  end

  def prev_path
    api_v1_reactions_url pagination_params(min_id: pagination_since_id) unless results.empty?
  end

  def pagination_collection
    results
  end

  def records_continue?
    results.size == limit_param(DEFAULT_STATUSES_LIMIT)
  end
end
