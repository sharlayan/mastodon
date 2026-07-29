# frozen_string_literal: true

class MisskeyCompat::ChartService
  CACHE_VERSION = 1
  CURRENT_CACHE_TTL = 5.minutes
  FINALIZED_CACHE_TTL = 30.days
  MAX_LIMIT = 500
  SPANS = { 'hour' => 1.hour, 'day' => 1.day }.freeze

  SCHEMAS = {
    active_users: %w(readWrite read write registeredWithinWeek registeredWithinMonth registeredWithinYear registeredOutsideWeek registeredOutsideMonth registeredOutsideYear),
    ap_request: %w(deliverFailed deliverSucceeded inboxReceived),
    drive: %w(local.incCount local.incSize local.decCount local.decSize remote.incCount remote.incSize remote.decCount remote.decSize),
    federation: %w(deliveredInstances inboxInstances stalled sub pub pubsub subActive pubActive),
    instance: %w(
      requests.failed requests.succeeded requests.received
      notes.total notes.inc notes.dec notes.diffs.normal notes.diffs.reply notes.diffs.renote notes.diffs.withFile
      users.total users.inc users.dec
      following.total following.inc following.dec followers.total followers.inc followers.dec
      drive.totalFiles drive.incFiles drive.decFiles drive.incUsage drive.decUsage
    ),
    notes: %w(local.total local.inc local.dec local.diffs.normal local.diffs.reply local.diffs.renote local.diffs.withFile remote.total remote.inc remote.dec remote.diffs.normal remote.diffs.reply remote.diffs.renote remote.diffs.withFile),
    user_drive: %w(totalCount totalSize incCount incSize decCount decSize),
    user_following: %w(local.followings.total local.followings.inc local.followings.dec local.followers.total local.followers.inc local.followers.dec remote.followings.total remote.followings.inc remote.followings.dec remote.followers.total remote.followers.inc remote.followers.dec),
    user_notes: %w(total inc dec diffs.normal diffs.reply diffs.renote diffs.withFile),
    user_pv: %w(upv.user pv.user upv.visitor pv.visitor),
    user_reactions: %w(local.count remote.count),
    users: %w(local.total local.inc local.dec remote.total remote.inc remote.dec),
  }.freeze

  STATUS_KINDS = %i(normal reply renote with_file).freeze
  EMPTY_STATUS_EVENT = { count: 0, normal: 0, reply: 0, renote: 0, with_file: 0 }.freeze

  Bucket = Struct.new(:start_at, :end_at) do
    def hash
      start_at.to_i.hash
    end

    def eql?(other)
      other.is_a?(Bucket) && start_at.to_i == other.start_at.to_i
    end
  end

  class InvalidParameter < StandardError
    attr_reader :param

    def initialize(param, message)
      @param = param
      super(message)
    end
  end

  def initialize(name:, span:, limit: nil, offset: nil, group: nil, suppressed: false)
    @name = name.to_sym
    @span = span.to_s
    @limit = parse_limit(limit)
    @group = group
    @suppressed = suppressed
    @latest = parse_latest(offset)

    raise InvalidParameter.new('#/properties/span', "must be one of #{SPANS.keys.join(', ')}") unless SPANS.key?(@span)
    raise InvalidParameter.new('#/properties/name', 'unknown chart') unless SCHEMAS.key?(@name)
  end

  def call
    return transpose(buckets.map { zero_record }) if @suppressed

    keys = buckets.index_with { |bucket| cache_key(bucket) }
    cached = Rails.cache.read_multi(*keys.values)
    records = keys.transform_values { |key| cached[key] }

    if records.value?(nil)
      generated = generate
      missing = records.select { |_bucket, record| record.nil? }.keys
      finalized, current = missing.partition { |bucket| bucket.end_at <= Time.current.utc }

      write_records(generated, finalized, FINALIZED_CACHE_TTL)
      write_records(generated, current, CURRENT_CACHE_TTL)
      missing.each { |bucket| records[bucket] = generated.fetch(bucket) }
    end

    transpose(records.values)
  end

  private

  def parse_limit(value)
    return 30 if value.nil?

    parsed = Integer(value, exception: false)
    numeric = Float(value, exception: false)
    valid = parsed&.between?(1, MAX_LIMIT) && numeric&.finite? && numeric == parsed
    raise InvalidParameter.new('#/properties/limit', "must be an integer between 1 and #{MAX_LIMIT}") unless valid

    parsed
  end

  def parse_latest(value)
    time = if value.nil?
             Time.current.utc
           else
             milliseconds = Float(value, exception: false)
             valid = milliseconds&.finite? && milliseconds == milliseconds.to_i
             raise InvalidParameter.new('#/properties/offset', 'must be a timestamp in milliseconds') unless valid

             Time.at(milliseconds / 1000).utc
           end

    @span == 'day' ? time.beginning_of_day : time.beginning_of_hour
  rescue RangeError
    raise InvalidParameter.new('#/properties/offset', 'must be a timestamp in milliseconds')
  end

  def buckets
    duration = SPANS.fetch(@span)

    @buckets ||= Array.new(@limit) do |index|
      start_at = @latest - (duration * index)
      Bucket.new(start_at, start_at + duration)
    end
  end

  def cache_key(bucket)
    group = @group.nil? ? '-' : Digest::SHA256.hexdigest(@group.to_s)
    "misskey_compat:chart:v#{CACHE_VERSION}:#{@name}:#{@span}:#{group}:#{bucket.start_at.to_i}"
  end

  def write_records(generated, selected, ttl)
    return if selected.empty?

    values = selected.to_h { |bucket| [cache_key(bucket), generated.fetch(bucket)] }
    Rails.cache.write_multi(values, expires_in: ttl)
  end

  def generate
    records = buckets.index_with { zero_record }

    case @name
    when :notes
      populate_notes(records)
    when :user_notes
      populate_notes(records, account_id: @group, prefix: nil)
    when :users
      populate_users(records)
    when :drive
      populate_drive(records)
    when :user_drive
      populate_drive(records, account_id: @group)
    when :user_following
      populate_user_following(records)
    when :user_reactions
      populate_user_reactions(records)
    when :active_users
      populate_active_users(records)
    when :federation
      populate_federation(records)
    when :instance
      populate_instance(records)
    end

    records
  end

  def zero_record
    SCHEMAS.fetch(@name).index_with { 0 }
  end

  def populate_notes(records, account_id: nil, prefix: :split)
    base = Status.unscoped
    base = base.where(account_id: account_id) if account_id

    if prefix == :split
      populate_status_partition(records, base.joins(:account).where(accounts: { domain: nil }), 'local.')
      populate_status_partition(records, base.joins(:account).where.not(accounts: { domain: nil }), 'remote.')
    else
      populate_status_partition(records, base, '')
    end
  end

  def populate_status_partition(records, scope, prefix)
    created = grouped_status_events(scope, :created_at)
    deleted = grouped_status_events(scope.where.not(deleted_at: nil), :deleted_at)
    running = scope.where(statuses: { created_at: ...buckets.first.end_at })
      .where('statuses.deleted_at IS NULL OR statuses.deleted_at >= ?', buckets.first.end_at)
      .count

    buckets.each do |bucket|
      inc = created.fetch(bucket.start_at.to_i, EMPTY_STATUS_EVENT)
      dec = deleted.fetch(bucket.start_at.to_i, EMPTY_STATUS_EVENT)
      record = records.fetch(bucket)
      record["#{prefix}total"] = running
      record["#{prefix}inc"] = inc[:count]
      record["#{prefix}dec"] = dec[:count]
      STATUS_KINDS.each do |kind|
        key = kind == :with_file ? 'withFile' : kind.to_s
        record["#{prefix}diffs.#{key}"] = inc[kind] - dec[kind]
      end
      running = running - inc[:count] + dec[:count]
    end
  end

  def grouped_status_events(scope, timestamp)
    scope = scope.reorder(nil)
    column = "statuses.#{timestamp}"
    rows = scope.where(timestamp => range)
      .group(Arel.sql(bucket_sql(column)))
      .pluck(
        Arel.sql(bucket_sql(column)),
        Arel.sql('COUNT(*)'),
        Arel.sql('COUNT(*) FILTER (WHERE statuses.in_reply_to_id IS NULL AND statuses.reblog_of_id IS NULL)'),
        Arel.sql('COUNT(*) FILTER (WHERE statuses.in_reply_to_id IS NOT NULL)'),
        Arel.sql('COUNT(*) FILTER (WHERE statuses.reblog_of_id IS NOT NULL)'),
        Arel.sql(<<~SQL.squish)
          COUNT(*) FILTER (
            WHERE COALESCE(cardinality(statuses.ordered_media_attachment_ids), 0) > 0
               OR EXISTS (SELECT 1 FROM media_attachments WHERE media_attachments.status_id = statuses.id)
          )
        SQL
      )

    rows.to_h do |bucket, count, normal, reply_count, renote, with_file|
      [bucket.to_time.to_i, { count: count, normal: normal, reply: reply_count, renote: renote, with_file: with_file }]
    end
  end

  def populate_users(records)
    populate_account_partition(records, Account.where(domain: nil), 'local.')
    populate_account_partition(records, Account.where.not(domain: nil), 'remote.')
  end

  def populate_account_partition(records, scope, prefix)
    created = grouped_count(scope, :created_at)
    running = scope.where(created_at: ...buckets.first.end_at).count

    buckets.each do |bucket|
      inc = created.fetch(bucket.start_at.to_i, 0)
      record = records.fetch(bucket)
      record["#{prefix}total"] = running
      record["#{prefix}inc"] = inc
      running -= inc
    end
  end

  def populate_drive(records, account_id: nil)
    scope = DriveFile.all
    scope = scope.where(account_id: account_id) if account_id
    created = grouped_count_and_sum(scope, :created_at, :storage_file_size)
    running_count = scope.where(created_at: ...buckets.first.end_at).count
    running_size = scope.where(created_at: ...buckets.first.end_at).sum(:storage_file_size).to_f / 1000

    buckets.each do |bucket|
      event = created.fetch(bucket.start_at.to_i, [0, 0])
      record = records.fetch(bucket)
      if account_id
        record['totalCount'] = running_count
        record['totalSize'] = running_size
        record['incCount'] = event[0]
        record['incSize'] = event[1]
      else
        record['local.incCount'] = event[0]
        record['local.incSize'] = event[1]
      end
      running_count -= event[0]
      running_size -= event[1]
    end
  end

  def populate_user_following(records)
    account = Account.find_by(id: @group)
    return if account.nil?

    populate_follow_partition(records, Follow.where(account_id: account.id).joins(:target_account).where(accounts: { domain: nil }), 'local.followings.')
    populate_follow_partition(records, Follow.where(account_id: account.id).joins(:target_account).where.not(accounts: { domain: nil }), 'remote.followings.')
    populate_follow_partition(records, Follow.where(target_account_id: account.id).joins(:account).where(accounts: { domain: nil }), 'local.followers.')
    populate_follow_partition(records, Follow.where(target_account_id: account.id).joins(:account).where.not(accounts: { domain: nil }), 'remote.followers.')
  end

  def populate_follow_partition(records, scope, prefix)
    created = grouped_count(scope, :created_at)
    running = scope.where(created_at: ...buckets.first.end_at).count
    buckets.each do |bucket|
      inc = created.fetch(bucket.start_at.to_i, 0)
      records[bucket]["#{prefix}total"] = running
      records[bucket]["#{prefix}inc"] = inc
      running -= inc
    end
  end

  def populate_user_reactions(records)
    base = StatusReaction.joins(:status, :account).where(statuses: { account_id: @group })
    populate_simple_events(records, base.where(accounts: { domain: nil }), 'local.count')
    populate_simple_events(records, base.where.not(accounts: { domain: nil }), 'remote.count')
  end

  def populate_simple_events(records, scope, key)
    grouped_count(scope, :created_at).each do |timestamp, count|
      bucket = bucket_by_timestamp[timestamp]
      records[bucket][key] = count if bucket
    end
  end

  def populate_active_users(records)
    activity = User.joins(:account).where(accounts: { domain: nil }).where(last_active_at: range)
    reads = grouped_distinct_count(activity, :last_active_at, 'users.account_id')
    writes = grouped_distinct_count(Status.joins(:account).where(accounts: { domain: nil }), :created_at, 'statuses.account_id')

    buckets.each do |bucket|
      read = reads.fetch(bucket.start_at.to_i, 0)
      write = writes.fetch(bucket.start_at.to_i, 0)
      record = records.fetch(bucket)
      record['read'] = read
      record['write'] = write
      record['readWrite'] = [read, write].min
    end

    populate_registration_age(records, activity)
  end

  def populate_registration_age(records, scope)
    rows = scope.reorder(nil).group(Arel.sql(bucket_sql('users.last_active_at')))
      .pluck(
        Arel.sql(bucket_sql('users.last_active_at')),
        Arel.sql("COUNT(DISTINCT users.account_id) FILTER (WHERE accounts.created_at >= users.last_active_at - INTERVAL '7 days')"),
        Arel.sql("COUNT(DISTINCT users.account_id) FILTER (WHERE accounts.created_at < users.last_active_at - INTERVAL '7 days')"),
        Arel.sql("COUNT(DISTINCT users.account_id) FILTER (WHERE accounts.created_at >= users.last_active_at - INTERVAL '30 days')"),
        Arel.sql("COUNT(DISTINCT users.account_id) FILTER (WHERE accounts.created_at < users.last_active_at - INTERVAL '30 days')"),
        Arel.sql("COUNT(DISTINCT users.account_id) FILTER (WHERE accounts.created_at >= users.last_active_at - INTERVAL '365 days')"),
        Arel.sql("COUNT(DISTINCT users.account_id) FILTER (WHERE accounts.created_at < users.last_active_at - INTERVAL '365 days')")
      )
    rows.each do |bucket, within_week, outside_week, within_month, outside_month, within_year, outside_year|
      record = records[bucket_by_timestamp.fetch(bucket.to_time.to_i)]
      record['registeredWithinWeek'] = within_week
      record['registeredOutsideWeek'] = outside_week
      record['registeredWithinMonth'] = within_month
      record['registeredOutsideMonth'] = outside_month
      record['registeredWithinYear'] = within_year
      record['registeredOutsideYear'] = outside_year
    end
  end

  def populate_federation(records)
    sub = Follow.joins(:account, :target_account).where(accounts: { domain: nil }).where.not(target_accounts_follows: { domain: nil })
    pub = Follow.joins(:account, :target_account).where.not(accounts: { domain: nil }).where(target_accounts_follows: { domain: nil })
    sub_first_seen = federation_first_seen(sub, 'target_accounts_follows.domain')
    pub_first_seen = federation_first_seen(pub, 'accounts.domain')
    pubsub_first_seen = sub_first_seen.keys.intersection(pub_first_seen.keys).index_with do |domain|
      [sub_first_seen.fetch(domain), pub_first_seen.fetch(domain)].max
    end

    buckets.each do |bucket|
      record = records[bucket]
      record['sub'] = count_seen_before(sub_first_seen, bucket.end_at)
      record['pub'] = count_seen_before(pub_first_seen, bucket.end_at)
      record['pubsub'] = count_seen_before(pubsub_first_seen, bucket.end_at)
      record['subActive'] = record['sub']
      record['pubActive'] = record['pub']
    end
  end

  def federation_first_seen(scope, domain_column)
    scope.reorder(nil).group(Arel.sql(domain_column)).minimum(:created_at)
  end

  def count_seen_before(first_seen, time)
    first_seen.count { |_domain, seen_at| seen_at < time }
  end

  def populate_instance(records)
    accounts = Account.where(domain: @group)
    populate_instance_statuses(records, accounts)
    populate_instance_accounts(records, accounts)
    populate_instance_follows(records, accounts)
    populate_instance_drive(records, accounts)
  end

  def populate_instance_statuses(records, accounts)
    base = Status.unscoped.where(account_id: accounts.select(:id))
    created = grouped_status_events(base, :created_at)
    deleted = grouped_status_events(base.where.not(deleted_at: nil), :deleted_at)
    running = base.where(statuses: { created_at: ...buckets.first.end_at })
      .where('statuses.deleted_at IS NULL OR statuses.deleted_at >= ?', buckets.first.end_at).count
    buckets.each do |bucket|
      inc = created.fetch(bucket.start_at.to_i, EMPTY_STATUS_EVENT)
      dec = deleted.fetch(bucket.start_at.to_i, EMPTY_STATUS_EVENT)
      record = records[bucket]
      record['notes.total'] = running
      record['notes.inc'] = inc[:count]
      record['notes.dec'] = dec[:count]
      STATUS_KINDS.each do |kind|
        key = kind == :with_file ? 'withFile' : kind.to_s
        record["notes.diffs.#{key}"] = inc[kind] - dec[kind]
      end
      running = running - inc[:count] + dec[:count]
    end
  end

  def populate_instance_accounts(records, accounts)
    created = grouped_count(accounts, :created_at)
    running = accounts.where(created_at: ...buckets.first.end_at).count
    buckets.each do |bucket|
      inc = created.fetch(bucket.start_at.to_i, 0)
      records[bucket]['users.total'] = running
      records[bucket]['users.inc'] = inc
      running -= inc
    end
  end

  def populate_instance_follows(records, accounts)
    populate_instance_follow_direction(records, Follow.where(account_id: accounts.select(:id)), 'following.')
    populate_instance_follow_direction(records, Follow.where(target_account_id: accounts.select(:id)), 'followers.')
  end

  def populate_instance_drive(records, accounts)
    scope = MediaAttachment.where(account_id: accounts.select(:id))
    created = grouped_count_and_sum(scope, :created_at, :file_file_size)
    running = scope.where(created_at: ...buckets.first.end_at).count
    buckets.each do |bucket|
      event = created.fetch(bucket.start_at.to_i, [0, 0])
      records[bucket]['drive.totalFiles'] = running
      records[bucket]['drive.incFiles'] = event[0]
      records[bucket]['drive.incUsage'] = event[1]
      running -= event[0]
    end
  end

  def populate_instance_follow_direction(records, scope, prefix)
    created = grouped_count(scope, :created_at)
    running = scope.where(created_at: ...buckets.first.end_at).count
    buckets.each do |bucket|
      inc = created.fetch(bucket.start_at.to_i, 0)
      records[bucket]["#{prefix}total"] = running
      records[bucket]["#{prefix}inc"] = inc
      running -= inc
    end
  end

  def grouped_count(scope, timestamp)
    scope = scope.reorder(nil)
    scope.where(timestamp => range).group(Arel.sql(bucket_sql(qualified_column(scope, timestamp)))).count.transform_keys { |time| time.to_time.to_i }
  end

  def grouped_distinct_count(scope, timestamp, expression)
    scope = scope.reorder(nil)
    column = qualified_column(scope, timestamp)
    scope.where(timestamp => range).group(Arel.sql(bucket_sql(column))).pluck(Arel.sql(bucket_sql(column)), Arel.sql("COUNT(DISTINCT #{expression})")).to_h { |time, count| [time.to_time.to_i, count] }
  end

  def grouped_count_and_sum(scope, timestamp, sum_column)
    scope = scope.reorder(nil)
    column = qualified_column(scope, timestamp)
    scope.where(timestamp => range).group(Arel.sql(bucket_sql(column))).pluck(Arel.sql(bucket_sql(column)), Arel.sql('COUNT(*)'), Arel.sql("COALESCE(SUM(#{scope.table_name}.#{sum_column}), 0) / 1000.0")).to_h { |time, count, sum| [time.to_time.to_i, [count, sum.to_f]] }
  end

  def qualified_column(scope, timestamp)
    "#{scope.table_name}.#{timestamp}"
  end

  def bucket_sql(column)
    "date_trunc('#{@span}', #{column} AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'"
  end

  def range
    @range ||= buckets.last.start_at...buckets.first.end_at
  end

  def bucket_by_timestamp
    @bucket_by_timestamp ||= buckets.index_by { |bucket| bucket.start_at.to_i }
  end

  def transpose(records)
    flat = SCHEMAS.fetch(@name).index_with { |key| records.map { |record| record.fetch(key) } }
    flat.each_with_object({}) do |(key, value), result|
      target = result
      parts = key.split('.')
      parts[0...-1].each { |part| target = (target[part] ||= {}) }
      target[parts.last] = value
    end
  end
end
