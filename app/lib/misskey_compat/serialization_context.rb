# frozen_string_literal: true

class MisskeyCompat::SerializationContext
  attr_reader :current_account, :account_id

  def self.for(statuses, current_account: nil)
    new(current_account: current_account).prime(Array(statuses))
  end

  def initialize(current_account: nil)
    @current_account = current_account
    @account_id = current_account&.id
    @user_cache = {}
    @instance_cache = {}
    @reaction_map = nil
    @own_votes_map = nil
  end

  def user(account)
    return nil if account.nil?

    @user_cache[account.id] ||= MisskeyCompat::UserSerializer.serialize(account, context: self)
  end

  def instance_info(domain)
    return @instance_cache[domain] if @instance_cache.key?(domain)

    @instance_cache[domain] = yield
  end

  def reactions_for(status)
    return status.reactions(@account_id) if @reaction_map.nil?

    @reaction_map[status.id] || []
  end

  def own_votes(poll)
    return [] if poll.nil? || @current_account.nil?
    return poll.own_votes(@current_account) if @own_votes_map.nil?

    @own_votes_map[poll.id] || []
  end

  def prime(statuses)
    expanded = expand(statuses)
    prime_reactions(expanded)
    prime_own_votes(expanded)
    self
  end

  private

  def expand(statuses)
    related = []

    statuses.each do |status|
      next if status.nil?

      related << status
      related << status.thread if status.thread
      related << status.reblog if status.reblog?

      quoted = status.quote&.quoted_status
      related << quoted if quoted
    end

    related.uniq(&:id)
  end

  def prime_reactions(statuses)
    status_ids = statuses.map(&:id).uniq
    return if status_ids.empty?

    @reaction_map = Hash.new { |hash, key| hash[key] = [] }

    grouped_reactions(status_ids).each do |record|
      @reaction_map[record.status_id] << record
    end
  end

  def grouped_reactions(status_ids)
    scope = StatusReaction.where(status_id: status_ids)

    if @current_account
      excluded = @current_account.excluded_from_timeline_account_ids
      scope = scope.where.not(account_id: excluded) if excluded.present?
    end

    records = scope
      .group(:status_id, :name, :custom_emoji_id)
      .order(:status_id, Arel.sql('MIN(created_at) ASC'))
      .select(:status_id, :name, :custom_emoji_id, Arel.sql('COUNT(*) AS count'), Arel.sql(reaction_me_column))
      .to_a

    ActiveRecord::Associations::Preloader.new(records: records, associations: { custom_emoji: :local_counterpart }).call
    records
  end

  def reaction_me_column
    return 'FALSE AS me' if @account_id.nil?

    <<~SQL.squish
      EXISTS(
        SELECT 1
        FROM status_reactions inner_reactions
        WHERE inner_reactions.account_id = #{@account_id.to_i}
          AND inner_reactions.status_id = status_reactions.status_id
          AND inner_reactions.name = status_reactions.name
          AND (
            inner_reactions.custom_emoji_id = status_reactions.custom_emoji_id
            OR inner_reactions.custom_emoji_id IS NULL
              AND status_reactions.custom_emoji_id IS NULL
          )
      ) AS me
    SQL
  end

  def prime_own_votes(statuses)
    return if @account_id.nil?

    poll_ids = statuses.filter_map { |status| status.preloadable_poll&.id }.uniq
    return if poll_ids.empty?

    @own_votes_map = Hash.new { |hash, key| hash[key] = [] }

    PollVote.where(poll_id: poll_ids, account_id: @account_id).pluck(:poll_id, :choice).each do |poll_id, choice|
      @own_votes_map[poll_id] << choice
    end
  end
end
