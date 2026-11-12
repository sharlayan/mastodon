# frozen_string_literal: true

require 'sidekiq/api'

class Api::MisskeyCompat::Admin::QueueController < Api::MisskeyCompat::Admin::ServerBaseController
  WEBHOOK_WORKERS = %w(MisskeyCompatWebhookDeliveryWorker Webhooks::DeliveryWorker).freeze
  DEFAULT_QUEUE_WORKERS = %w(PollExpirationNotifyWorker PublishScheduledStatusWorker).freeze
  QUEUES = {
    'system' => { queue: 'scheduler' },
    'endedPollNotification' => { queue: 'default', only: %w(PollExpirationNotifyWorker) },
    'postScheduledNote' => { queue: 'default', only: %w(PublishScheduledStatusWorker) },
    'deliver' => { queue: 'push', except: WEBHOOK_WORKERS },
    'inbox' => { queue: 'ingress' },
    'db' => { queue: 'pull' },
    'relationship' => { queue: 'default', except: DEFAULT_QUEUE_WORKERS },
    'objectStorage' => nil,
    'userWebhookDeliver' => { queue: 'push', only: %w(MisskeyCompatWebhookDeliveryWorker) },
    'systemWebhookDeliver' => { queue: 'push', only: %w(Webhooks::DeliveryWorker) },
  }.freeze
  JOB_STATES = %w(active wait delayed completed failed paused).freeze
  CLEAR_STATES = %w(* completed wait active paused prioritized delayed failed).freeze
  RETURN_LIMIT = 100
  SEARCH_LIMIT = 1_000
  EMPTY_METRICS = { meta: { count: 0, prevTS: 0, prevCount: 0 }, data: [], count: 0 }.freeze

  misskey_admin_endpoint :stats, kind: 'read:admin:emoji', permission: :view_devops
  misskey_admin_endpoint :queues, :queue_stats, :jobs, :show_job, :show_job_logs, :deliver_delayed, :inbox_delayed, kind: 'read:admin:queue', permission: :view_devops
  misskey_admin_endpoint :clear, :promote_jobs, :retry_job, :remove_job, kind: 'write:admin:queue', permission: :view_devops

  before_action :set_queue, except: [:stats, :queues, :deliver_delayed, :inbox_delayed]
  before_action :set_job, only: [:show_job, :retry_job, :remove_job]

  def stats
    render json: %w(deliver inbox db objectStorage).index_with { |name| counts(QUEUES[name]) }
  end

  def queues
    render json: QUEUES.map { |name, definition| summary(name, definition) }
  end

  def queue_stats
    info = Sidekiq.default_configuration.redis_info

    render json: summary(@name, @definition).merge(
      qualifiedName: @definition ? "queue:#{@definition[:queue]}" : @name,
      db: {
        version: info['redis_version'],
        mode: info['redis_mode'] || 'standalone',
        runId: info['run_id'],
        processId: info['process_id'].to_i,
        port: info['tcp_port'].to_i,
        os: info['os'],
        uptime: info['uptime_in_seconds'].to_i,
        memory: {
          total: info['total_system_memory'].to_i.nonzero? || info['maxmemory'].to_i,
          used: info['used_memory'].to_i,
          fragmentationRatio: info['mem_fragmentation_ratio'].to_i,
          peak: info['used_memory_peak'].to_i,
        },
        clients: { connected: info['connected_clients'].to_i, blocked: info['blocked_clients'].to_i },
      }
    )
  end

  def jobs
    states = params[:state]
    return render_invalid_param('#/properties/state', 'must be array of job states') unless states.is_a?(Array) && states.all? { |state| JOB_STATES.include?(state) }
    return if params.key?(:search) && !require_string_param!(:search)

    entries = states.uniq.flat_map { |state| entries_for(@definition, state, limit: params[:search].present? ? SEARCH_LIMIT : RETURN_LIMIT) }
    entries = filter_search(entries, params[:search]) if params[:search].present?

    render json: entries.first(RETURN_LIMIT).map { |state, entry| pack(state, entry) }
  end

  def show_job
    render json: pack(*@job)
  end

  def show_job_logs
    render json: []
  end

  def retry_job
    state, entry = @job
    if state == 'failed' || (state == 'delayed' && entry.parent.is_a?(Sidekiq::RetrySet))
      entry.retry
    elsif state == 'delayed'
      entry.add_to_queue
    end

    head 204
  end

  def remove_job
    state, entry = @job
    # DESTRUCTIVE: Removes the Sidekiq job permanently; it will not run.
    # 파괴적: Sidekiq 작업을 영구히 제거해 실행되지 않게 합니다.
    entry.delete unless state == 'active'

    head 204
  end

  def promote_jobs
    sorted_entries(@definition, Sidekiq::ScheduledSet.new).each(&:add_to_queue)
    sorted_entries(@definition, Sidekiq::RetrySet.new).each(&:retry)

    head 204
  end

  def clear
    state = params[:state]
    return render_invalid_param('#/properties/state', "must be one of #{CLEAR_STATES.join(', ')}") unless CLEAR_STATES.include?(state)

    # DESTRUCTIVE: Deletes queued, scheduled, retrying or dead Sidekiq jobs of the mapped queue.
    # 파괴적: 대응하는 큐의 대기·예약·재시도·실패 Sidekiq 작업을 삭제합니다.
    %w(wait delayed failed).each do |target|
      entries_for(@definition, target, limit: nil).map(&:last).each(&:delete) if [target, '*'].include?(state)
    end

    head 204
  end

  def deliver_delayed
    render json: delayed_hosts('deliver') { |entries| entries.filter_map { |entry| host_of(entry.args[2]) } }
  end

  def inbox_delayed
    render json: delayed_hosts('inbox') { |entries| Account.where(id: entries.map { |entry| entry.args[0] }).pluck(:domain).compact }
  end

  private

  def set_queue
    @name = params[:queue]
    return render_invalid_param('#/properties/queue', "must be one of #{QUEUES.keys.join(', ')}") unless QUEUES.key?(@name)

    @definition = QUEUES[@name]
  end

  def set_job
    jid = params[:jobId]
    return render_invalid_param('#/properties/jobId', 'must be string') unless jid.is_a?(String)

    @job = find_job(jid)
    render_error('No such job', 'NO_SUCH_JOB', 404) if @job.nil?
  end

  def find_job(jid)
    return nil if @definition.nil?

    JOB_STATES.each do |state|
      entry = entries_for(@definition, state, limit: nil).find { |_state, candidate| job_id(candidate) == jid }
      return entry if entry
    end
    nil
  end

  def summary(name, definition)
    {
      name: name,
      counts: counts(definition),
      isPaused: false,
      metrics: { completed: EMPTY_METRICS, failed: EMPTY_METRICS },
    }
  end

  def counts(definition)
    {
      waiting: entries_for(definition, 'wait', limit: nil).size,
      active: entries_for(definition, 'active', limit: nil).size,
      completed: 0,
      failed: entries_for(definition, 'failed', limit: nil).size,
      delayed: entries_for(definition, 'delayed', limit: nil).size,
    }
  end

  def entries_for(definition, state, limit:)
    return [] if definition.nil?

    entries = case state
              when 'wait'
                Sidekiq::Queue.new(definition[:queue]).select { |entry| class_allowed?(definition, entry.klass) }
              when 'delayed'
                sorted_entries(definition, Sidekiq::ScheduledSet.new) + sorted_entries(definition, Sidekiq::RetrySet.new)
              when 'failed'
                sorted_entries(definition, Sidekiq::DeadSet.new)
              when 'active'
                Sidekiq::WorkSet.new.filter_map { |_process, _thread, work| work if work.queue == definition[:queue] && class_allowed?(definition, work.job.klass) }
              else
                []
              end
    entries = entries.first(limit) if limit
    entries.map { |entry| [state, entry] }
  end

  def sorted_entries(definition, set)
    return [] if definition.nil?

    set.select { |entry| entry.queue == definition[:queue] && class_allowed?(definition, entry.klass) }
  end

  def class_allowed?(definition, klass)
    return definition[:only].include?(klass) if definition[:only]
    return definition[:except].exclude?(klass) if definition[:except]

    true
  end

  def job_id(entry)
    entry.is_a?(Sidekiq::Work) ? entry.job.jid : entry.jid
  end

  def filter_search(entries, search)
    terms = search.downcase.split
    entries.select do |_state, entry|
      record = entry.is_a?(Sidekiq::Work) ? entry.job : entry
      text = record.item.to_json.downcase
      terms.all? { |term| text.include?(term) }
    end
  end

  def pack(state, entry)
    record = entry.is_a?(Sidekiq::Work) ? entry.job : entry
    item = record.item
    failed_at = item['failed_at'] || item['retried_at']
    backtrace = Array(record.error_backtrace).compact_blank.reverse

    {
      id: record.jid,
      name: record.display_class,
      data: { args: record.display_args },
      opts: { queue: record.queue, attempts: item['retry'].is_a?(Integer) ? item['retry'] : nil, delay: delay_ms(state, entry) }.compact,
      timestamp: to_ms(record.created_at),
      processedOn: state == 'active' ? to_ms(entry.run_at) : nil,
      finishedOn: failed_at ? to_ms(Time.zone.at(failed_at.to_f)) : nil,
      progress: {},
      attempts: item['retry_count'].to_i + (item['error_message'] ? 1 : 0),
      delay: delay_ms(state, entry),
      failedReason: item['error_message'] ? "#{item['error_class']}: #{item['error_message']}" : nil,
      stacktrace: backtrace,
      returnValue: nil,
      isFailed: item['error_message'].present? || backtrace.any?,
    }.compact
  end

  def delay_ms(state, entry)
    return 0 unless state == 'delayed'

    [((entry.at.to_f - Time.now.to_f) * 1000).round, 0].max
  end

  def to_ms(time)
    time ? (time.to_f * 1000).round : 0
  end

  def delayed_hosts(name)
    hosts = yield(entries_for(QUEUES[name], 'delayed', limit: nil).map(&:last))
    hosts.tally.sort_by { |host, count| [-count, host] }
  end

  def host_of(url)
    Addressable::URI.parse(url.to_s).host
  rescue Addressable::URI::InvalidURIError
    nil
  end
end
