# frozen_string_literal: true

require 'open3'

class Api::MisskeyCompat::Admin::SystemController < Api::MisskeyCompat::Admin::ServerBaseController
  include Redisable

  misskey_admin_endpoint :server_info, kind: 'read:admin:server-info', permission: :view_devops
  misskey_admin_endpoint :index_stats, kind: 'read:admin:index-stats', role: :admin, permission: :view_devops
  misskey_admin_endpoint :table_stats, kind: 'read:admin:table-stats', role: :admin, permission: :view_devops

  TABLE_STATS_SQL = <<~SQL.squish
    SELECT relname AS "table", reltuples AS "count", pg_total_relation_size(C.oid) AS "size"
    FROM pg_class C LEFT JOIN pg_namespace N ON (N.oid = C.relnamespace)
    WHERE nspname NOT IN ('pg_catalog', 'information_schema')
      AND C.relkind <> 'i'
      AND nspname !~ '^pg_toast'
  SQL

  def server_info
    fs_total, fs_used = filesystem_usage

    render json: {
      machine: Socket.gethostname,
      os: Etc.uname[:sysname].to_s.downcase,
      node: "Ruby #{RUBY_VERSION}",
      psql: connection.select_value('SHOW server_version'),
      redis: redis_version,
      cpu: { model: cpu_model, cores: Etc.nprocessors },
      mem: { total: memory_total },
      fs: { total: fs_total, used: fs_used },
      net: { interface: default_interface },
    }
  end

  def index_stats
    render json: connection.select_all('SELECT schemaname, tablename, indexname, tablespace, indexdef FROM pg_indexes').to_a
  end

  def table_stats
    rows = connection.select_all(TABLE_STATS_SQL).to_a
    render json: rows.to_h { |row| [row['table'], { count: row['count'].to_i, size: row['size'].to_i }] }
  end

  private

  def connection
    ActiveRecord::Base.connection
  end

  def redis_version
    with_redis { |redis_connection| redis_connection.info('server')['redis_version'] }
  rescue Redis::BaseError
    nil
  end

  def cpu_model
    File.foreach('/proc/cpuinfo') { |line| return line.split(':', 2).last.strip if line.start_with?('model name') }
    '?'
  rescue SystemCallError
    '?'
  end

  def memory_total
    File.foreach('/proc/meminfo') { |line| return line.split[1].to_i * 1024 if line.start_with?('MemTotal:') }
    0
  rescue SystemCallError
    0
  end

  def filesystem_usage
    output, status = Open3.capture2('df', '-Pk', Rails.root.to_s)
    return [0, 0] unless status.success?

    columns = output.lines.last.to_s.split
    [columns[1].to_i * 1024, columns[2].to_i * 1024]
  rescue SystemCallError
    [0, 0]
  end

  def default_interface
    File.foreach('/proc/net/route').drop(1).each do |line|
      interface, destination = line.split
      return interface if destination == '00000000'
    end
    nil
  rescue SystemCallError
    nil
  end
end
