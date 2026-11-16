# frozen_string_literal: true

class Api::MisskeyCompat::ReversiController < Api::MisskeyCompat::BaseController
  NO_SUCH_GAME_IDS = {
    'show_game' => 'f13a03db-fae1-46c9-87f3-43c8165419e1',
    'surrender' => 'ace0b11f-e0a6-4076-a30d-e8284c81b2df',
    'verify' => '8fb05624-b525-43dd-90f7-511852bdfeee',
  }.freeze
  NO_SUCH_USER_ID = '0b4f0559-b484-4e31-9581-3f73cee89b28'
  TARGET_IS_YOURSELF_ID = '96fd7bd6-d2bc-426c-a865-d055dcd2828e'
  ALREADY_ENDED_ID = '6c2ad4a6-cbf1-4a5b-b187-b772826cfc6d'
  SURRENDER_ACCESS_DENIED_ID = '6e04164b-a992-4c93-8489-2123069973e1'

  requires_write_scope :match, :cancel_match, :surrender
  requires_misskey_permission 'read:account', :games, :invitations, :show_game, :verify
  requires_misskey_permission 'write:account', :match, :cancel_match, :surrender

  before_action :require_user!, only: [:match, :cancel_match, :invitations, :surrender]
  before_action :require_user_if_authenticated!, only: [:games, :show_game, :verify]
  before_action :require_object_body!
  before_action :set_game, only: [:show_game, :surrender, :verify]

  def match
    return unless valid_nullable_user_id? && valid_booleans?(:noIrregularRules, :multiple)

    target_id = params[:userId].presence
    return render_error('Target user is yourself', 'TARGET_IS_YOURSELF', 400, id: TARGET_IS_YOURSELF_ID) if target_id == current_account.id.to_s

    game = if target_id
             target = compat_id?(target_id) ? Account.without_suspended.find_by(id: target_id) : nil
             return render_error('No such user', 'NO_SUCH_USER', 404, id: NO_SUCH_USER_ID) if target.nil?

             service.match_specific_user(current_account, target, multiple: params[:multiple] == true)
           else
             service.match_any_user(current_account, no_irregular_rules: params[:noIrregularRules] == true, multiple: params[:multiple] == true)
           end

    game ? render(json: MisskeyCompat::ReversiGameSerializer.detail(game)) : head(204)
  end

  def cancel_match
    return unless valid_nullable_user_id?

    target_id = params[:userId].presence
    if target_id
      service.cancel_match_specific_user(current_account, target_id) if compat_id?(target_id)
    else
      service.cancel_match_any(current_account)
    end

    head 204
  end

  def invitations
    ids = service.invitation_ids(current_account.id)
    accounts = Account.without_suspended.where(id: ids).index_by { |account| account.id.to_s }
    ordered = ids.filter_map { |id| accounts[id] }
    collection = MisskeyCompat::UserCollectionContext.for(ordered, viewer: current_account)

    render json: ordered.map { |account| MisskeyCompat::UserSerializer.serialize(account, collection: collection) }
  end

  def games
    return unless valid_booleans?(:my)

    scope = MisskeyReversiGame.includes(:account1, :account2)
    scope = params[:my] == true && current_account ? scope.involving(current_account) : scope.started
    scope = apply_compat_pagination_dates(scope)
    scope = scope.where(id: ...params[:untilId].to_i) if params[:untilId].present?
    scope = scope.where('misskey_reversi_games.id > ?', params[:sinceId].to_i) if params[:sinceId].present?
    games = scope.order(id: forward_pagination? ? :asc : :desc).limit(pagination_limit(default: 10, max: 100)).to_a

    render json: MisskeyCompat::ReversiGameSerializer.many(games)
  end

  def show_game
    render json: MisskeyCompat::ReversiGameSerializer.detail(@game)
  end

  def surrender
    return render_error('That game has already ended', 'ALREADY_ENDED', 400, id: ALREADY_ENDED_ID) if @game.ended?
    return render_error('Access denied', 'ACCESS_DENIED', 403, id: SURRENDER_ACCESS_DENIED_ID) unless @game.participant?(current_account)

    service.surrender(@game, current_account)
    head 204
  end

  def verify
    return render_invalid_param('#/properties/crc32', 'must be string') unless params[:crc32].is_a?(String)

    game = service.desynced_game(@game, params[:crc32])
    render json: game ? { desynced: true, game: MisskeyCompat::ReversiGameSerializer.detail(game) } : { desynced: false }
  end

  private

  def service
    @service ||= MisskeyCompat::ReversiService.new
  end

  def set_game
    return render_invalid_param('#/properties/gameId', 'must be string') unless params[:gameId].is_a?(String)

    @game = MisskeyReversiGame.includes(:account1, :account2).find_by(id: params[:gameId]) if compat_id?(params[:gameId])
    render_error('No such game', 'NO_SUCH_GAME', 404, id: NO_SUCH_GAME_IDS[action_name]) if @game.nil?
  end

  def require_object_body!
    object_body!
  end

  def valid_nullable_user_id?
    return true if params[:userId].nil? || params[:userId].is_a?(String)

    render_invalid_param('#/properties/userId', 'must be string or null')
    false
  end

  def valid_booleans?(*keys)
    key = keys.find { |name| params.key?(name) && params[name] != true && params[name] != false }
    return true if key.nil?

    render_invalid_param("#/properties/#{key}", 'must be boolean')
    false
  end
end
