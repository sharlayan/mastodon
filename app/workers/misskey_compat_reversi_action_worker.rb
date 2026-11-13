# frozen_string_literal: true

class MisskeyCompatReversiActionWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'default', retry: false

  def perform(account_id, game_id, type, body = nil)
    return unless Setting.misskey_compat_enabled

    service = MisskeyCompat::ReversiService.new
    return service.start_game(game_id) if type == 'start'

    account = Account.local.find_by(id: account_id)
    return unless account&.user&.functional?

    case type
    when 'ready'
      service.ready(game_id, account, body) if [true, false].include?(body)
    when 'updateSettings'
      service.update_settings(game_id, account, body['key'], body['value']) if body.is_a?(Hash)
    when 'cancel'
      service.cancel_game(game_id, account)
    when 'putStone'
      service.put_stone(game_id, account, body['pos'], body['id']) if body.is_a?(Hash) && body['pos'].is_a?(Integer) && body['id'].is_a?(String)
    when 'claimTimeIsUp'
      service.check_timeout(game_id)
    end
  end
end
