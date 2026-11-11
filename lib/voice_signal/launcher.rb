# frozen_string_literal: true

require 'dotenv'
require 'uri'

module VoiceSignal
  class Launcher
    MODES = %w(auto binary docker).freeze
    PULL_POLICIES = %w(always missing never).freeze
    DEFAULT_IMAGE = 'ghcr.io/sharlayan/mastodon-voice-signal:edge'
    FORWARDED_VARIABLES = %w(
      LOCAL_DOMAIN WEB_DOMAIN SECRET_KEY_BASE DATABASE_URL DB_HOST DB_PORT DB_NAME DB_USER DB_PASS DB_SSLMODE
      VOICE_SIGNAL_PATH VOICE_SIGNAL_BIND VOICE_SIGNAL_PORT VOICE_SIGNAL_TRUSTED_PROXIES VOICE_SIGNAL_MAX_CONNECTIONS
      VOICE_SIGNAL_UPGRADES_PER_MINUTE VOICE_SIGNAL_DB_POOL VOICE_SIGNAL_EXIT_ON_STDIN_EOF
    ).freeze
    MIN_BACKOFF = 1
    MAX_BACKOFF = 60
    STABLE_AFTER = 60
    STOP_TIMEOUT = 10

    class ConfigurationError < StandardError; end

    attr_reader :environment, :mode

    def self.environment_for(root, env = ENV)
      rails_env = env.fetch('RAILS_ENV') { env.fetch('RACK_ENV', 'production') }
      files = [".env.#{rails_env}.local", rails_env == 'test' ? nil : '.env.local', ".env.#{rails_env}", '.env'].compact
      merged = files.reverse.each_with_object({}) do |name, values|
        path = File.join(root, name)
        values.merge!(Dotenv.parse(path)) if File.file?(path)
      end

      merged.merge(env.to_h)
    end

    def self.from_environment(root:, env: ENV, log: ->(message) { warn(message) })
      environment = environment_for(root, env)
      mode = environment['VOICE_SIGNAL_SPAWN'].to_s.strip.downcase
      return if mode.empty? || %w(false 0 off no).include?(mode)

      new(root:, environment:, mode:, log:)
    end

    def initialize(root:, environment:, mode:, log: ->(message) { warn(message) })
      raise ConfigurationError, "VOICE_SIGNAL_SPAWN must be one of #{MODES.join(', ')}" unless MODES.include?(mode)

      @root = root
      @mode = mode
      @log = log
      @environment = environment.merge(
        'VOICE_SIGNAL_EXIT_ON_STDIN_EOF' => '1',
        'VOICE_SIGNAL_BIND' => environment['VOICE_SIGNAL_BIND'].to_s.empty? ? '127.0.0.1' : environment['VOICE_SIGNAL_BIND']
      )
      @mutex = Mutex.new
      @wakeup = ConditionVariable.new
      @stopping = false
      @pid = nil
      @thread = nil
    end

    def command
      @command ||= case mode
                   when 'binary' then binary_command || raise(ConfigurationError, 'No voice signal build found; run `bin/rails voice_signal:publish` or set VOICE_SIGNAL_BINARY')
                   when 'docker' then docker_command || raise(ConfigurationError, 'The docker command is not available')
                   else binary_command || docker_command || raise(ConfigurationError, 'Neither a voice signal build nor docker is available')
                   end
    end

    def start
      command
      @thread ||= Thread.new { supervise }
      self
    rescue ConfigurationError => e
      @log.call("[voice-signal] not started: #{e.message}")
      nil
    end

    def stop
      Thread.new { stop_supervisor }.join
    end

    def running?
      @mutex.synchronize { !@pid.nil? }
    end

    def pid
      @mutex.synchronize { @pid }
    end

    private

    def stop_supervisor
      thread = nil
      @mutex.synchronize do
        @stopping = true
        thread = @thread
        @wakeup.broadcast
        signal('TERM')
      end
      return if thread.nil?

      return if thread.join(STOP_TIMEOUT)

      @mutex.synchronize { signal('KILL') }
      thread.join(STOP_TIMEOUT)
    end

    def supervise
      backoff = MIN_BACKOFF

      until stopping?
        remove_stale_container if docker?
        started_at = monotonic
        status = run_once
        break if stopping?

        backoff = MIN_BACKOFF if monotonic - started_at >= STABLE_AFTER
        @log.call("[voice-signal] exited (#{status&.exitstatus || status&.termsig || 'unknown'}); restarting in #{backoff}s")
        wait(backoff)
        backoff = [backoff * 2, MAX_BACKOFF].min
      end
    end

    def run_once
      reader, writer = IO.pipe
      pid = @mutex.synchronize do
        return if @stopping

        @pid = Process.spawn(@environment, *command, in: reader, out: $stdout, err: $stderr, chdir: @root)
      end
      reader.close
      @log.call("[voice-signal] started #{docker? ? 'container' : 'process'} (pid #{pid})")

      _, status = Process.wait2(pid)
      status
    rescue SystemCallError => e
      @log.call("[voice-signal] could not start: #{e.message}")
      nil
    ensure
      @mutex.synchronize { @pid = nil }
      reader&.close unless reader&.closed?
      writer&.close unless writer&.closed?
    end

    def signal(name)
      Process.kill(name, @pid) if @pid
    rescue Errno::ESRCH
      nil
    end

    def wait(seconds)
      @mutex.synchronize { @wakeup.wait(@mutex, seconds) unless @stopping }
    end

    def stopping?
      @mutex.synchronize { @stopping }
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def docker?
      command.first == docker_executable
    end

    def binary_command
      configured = @environment['VOICE_SIGNAL_BINARY'].to_s
      return command_for(File.expand_path(configured, @root)) unless configured.empty?

      executable = File.join(@root, 'voice_signal', 'publish', 'VoiceSignal')
      return [executable] if File.file?(executable) && File.executable?(executable)

      command_for(File.join(@root, 'voice_signal', 'publish', 'VoiceSignal.dll'))
    end

    def command_for(path)
      return unless File.file?(path)
      return [path] unless path.end_with?('.dll')

      dotnet = find_executable('dotnet')
      [dotnet, path] if dotnet
    end

    def docker_command
      return unless docker_executable

      pull = @environment['VOICE_SIGNAL_IMAGE_PULL'].to_s.empty? ? 'missing' : @environment['VOICE_SIGNAL_IMAGE_PULL']
      raise ConfigurationError, "VOICE_SIGNAL_IMAGE_PULL must be one of #{PULL_POLICIES.join(', ')}" unless PULL_POLICIES.include?(pull)

      image = @environment['VOICE_SIGNAL_IMAGE'].to_s.empty? ? DEFAULT_IMAGE : @environment['VOICE_SIGNAL_IMAGE']

      [
        docker_executable, 'run', '--rm', '--interactive', '--name', container_name, "--pull=#{pull}",
        '--network', 'host', '--user', "#{Process.uid}:#{Process.gid}",
        *socket_volumes.flat_map { |path| ['--volume', "#{path}:#{path}"] },
        *FORWARDED_VARIABLES.select { |name| @environment.key?(name) }.flat_map { |name| ['--env', name] },
        image
      ]
    end

    def container_name
      "mastodon-voice-signal-#{@environment.fetch('VOICE_SIGNAL_PORT', '4100')}"
    end

    def remove_stale_container
      system(docker_executable, 'rm', '--force', container_name, out: File::NULL, err: File::NULL)
    end

    def socket_volumes
      hosts = [@environment['DB_HOST'].to_s]
      url = @environment['DATABASE_URL'].to_s
      hosts << URI.decode_www_form(URI(url).query.to_s).to_h['host'].to_s unless url.empty?
      hosts.select { |host| host.start_with?('/') && File.directory?(host) }.uniq
    rescue URI::InvalidURIError
      []
    end

    def docker_executable
      return @docker_executable if defined?(@docker_executable)

      @docker_executable = find_executable('docker')
    end

    def find_executable(name)
      @environment.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |directory|
        path = File.join(directory, name)
        return path if File.file?(path) && File.executable?(path)
      end

      nil
    end
  end
end
