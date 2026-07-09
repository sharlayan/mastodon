# frozen_string_literal: true

class Api::MisskeyCompat::AntennasController < Api::MisskeyCompat::BaseController
  before_action :require_user!

  def index
    render json: current_account.antennas.order(id: :desc).map { |antenna| serialize(antenna) }
  end

  def notes
    antenna = current_account.antennas.find(params[:antennaId])
    statuses = AntennaFeed.new(antenna).get(pagination_limit, params[:untilId].presence, params[:sinceId].presence).to_a
    Status.preload_cacheable_associations(statuses)
    render json: statuses.map { |status| MisskeyCompat::NoteSerializer.serialize(status, current_account: current_account) }
  rescue ActiveRecord::RecordNotFound
    render_error('No such antenna', 'NO_SUCH_ANTENNA', 404)
  end

  private

  def serialize(antenna)
    {
      id: antenna.id.to_s,
      createdAt: antenna.created_at.iso8601,
      name: antenna.title,
      keywords: nest_keywords(antenna.keywords),
      excludeKeywords: nest_keywords(antenna.exclude_keywords),
      users: [],
      caseSensitive: false,
      notify: false,
      isActive: antenna.available,
      hasUnreadNote: false,
    }
  end

  def nest_keywords(keywords)
    list = Array(keywords).flatten.compact_blank
    list.empty? ? [] : [list]
  end
end
