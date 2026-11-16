# frozen_string_literal: true

class MisskeyCompat::ReversiGameSerializer
  class << self
    def detail(game, users: nil)
      users ||= users_for([game])
      lite(game, users: users).merge(
        form1: nil,
        form2: nil,
        user1Ready: game.account1_ready,
        user2Ready: game.account2_ready,
        logs: game.logs,
        map: game.map
      )
    end

    def lite(game, users: nil)
      users ||= users_for([game])
      user1 = users[game.account1_id]
      user2 = users[game.account2_id]

      {
        id: mid(game.id),
        createdAt: game.created_at.iso8601(3),
        startedAt: game.started_at&.iso8601(3),
        endedAt: game.ended_at&.iso8601(3),
        isStarted: game.started?,
        isEnded: game.ended?,
        user1Id: mid(game.account1_id),
        user2Id: mid(game.account2_id),
        user1: user1,
        user2: user2,
        winnerId: mid(game.winner_account_id),
        winner: game.winner_account_id ? users[game.winner_account_id] : nil,
        surrenderedUserId: mid(game.surrendered_account_id),
        timeoutUserId: mid(game.timeout_account_id),
        black: game.black,
        bw: MisskeyReversiGame::BW_VALUES.include?(game.bw) ? game.bw : 'random',
        isLlotheo: game.llotheo,
        canPutEverywhere: game.can_put_everywhere,
        loopedBoard: game.looped_board,
        timeLimitForEachTurn: game.time_limit_for_each_turn,
        noIrregularRules: game.no_irregular_rules,
      }
    end

    def many(games, detailed: false)
      users = users_for(games)
      games.map { |game| detailed ? detail(game, users: users) : lite(game, users: users) }
    end

    private

    def users_for(games)
      accounts = games.flat_map { |game| [game.account1, game.account2] }.uniq
      collection = MisskeyCompat::UserCollectionContext.for(accounts)
      accounts.to_h { |account| [account.id, MisskeyCompat::UserSerializer.serialize(account, collection: collection)] }
    end

    def mid(id)
      MisskeyCompat::MiId.encode(id)
    end
  end
end
