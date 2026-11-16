# frozen_string_literal: true

class Api::MisskeyCompat::BubbleGameController < Api::MisskeyCompat::BaseController
  INVALID_SEED_ID = 'eb627bc7-574b-4a52-a860-3c3eae772b88'
  MAX_SCORE = (2**31) - 1
  RANKING_CACHE_TTL = 60.seconds

  requires_write_scope :register
  requires_misskey_permission 'write:account', :register

  before_action :require_user!, only: :register

  def register
    return unless object_body!
    return unless valid_register_params?
    return if rate_limited?(:misskey_compat_bubble_game_interval) || rate_limited?(:misskey_compat_bubble_game)

    seeded_at = seed_time(params[:seed])
    now = Time.current
    return render_error('Provided seed is invalid.', 'INVALID_SEED', 400, id: INVALID_SEED_ID) if seeded_at.nil? || seeded_at > now || seeded_at < now - MisskeyBubbleGameRecord::SEED_MAX_AGE # rubocop:disable I18n/RailsI18n/DecorateString

    MisskeyBubbleGameRecord.create!(
      account: current_account,
      seed: params[:seed],
      seeded_at: seeded_at,
      score: params[:score],
      logs: params[:logs],
      game_mode: params[:gameMode],
      game_version: params[:gameVersion]
    )
    head 204
  end

  def ranking
    return render_invalid_param('#/properties/gameMode', 'must be a string') unless params[:gameMode].is_a?(String)

    body = Rails.cache.fetch("misskey_compat:bubble_game:ranking:#{Digest::SHA256.hexdigest(params[:gameMode])}", expires_in: RANKING_CACHE_TTL) do
      records = MisskeyBubbleGameRecord.ranking(params[:gameMode]).includes(:account).to_a
      records.map do |record|
        entry = { id: MisskeyCompat::MiId.encode(record.id), score: record.score }
        entry[:user] = MisskeyCompat::UserSerializer.serialize(record.account) unless record.account.unavailable?
        entry
      end
    end

    render json: body
  end

  private

  def valid_register_params?
    return invalid('#/properties/score', 'must be a non-negative integer') unless params[:score].is_a?(Integer) && params[:score].between?(0, MAX_SCORE)
    return invalid('#/properties/seed', 'must be a string of 1 to 1024 characters') unless params[:seed].is_a?(String) && params[:seed].length.between?(1, 1024)
    return invalid('#/properties/logs', 'must be an array of number arrays') unless numeric_logs?(params[:logs])
    return invalid('#/properties/gameMode', 'must be a string') unless params[:gameMode].is_a?(String)
    return invalid('#/properties/gameVersion', 'must be an integer') unless params[:gameVersion].is_a?(Integer) && params[:gameVersion].between?(-MAX_SCORE - 1, MAX_SCORE)

    true
  end

  def invalid(param, reason)
    render_invalid_param(param, reason)
    false
  end

  def numeric_logs?(logs)
    logs.is_a?(Array) && logs.all? { |entry| entry.is_a?(Array) && entry.all?(Numeric) }
  end

  def seed_time(seed)
    digits = seed[/\A\s*[+-]?\d+/]
    return if digits.nil?

    Time.zone.at(Integer(digits.strip, 10) / 1000.0)
  rescue RangeError
    nil
  end
end
