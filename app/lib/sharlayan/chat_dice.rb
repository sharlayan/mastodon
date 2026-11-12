# frozen_string_literal: true

class Sharlayan::ChatDice
  include Redisable

  class Error < Sharlayan::ChatService::Error
    # rubocop:disable-next I18n/RailsI18n/DecorateString
    MESSAGES = {
      invalid: 'Invalid dice notation.',
      limit: 'The dice roll exceeds the execution limits.',
      busy: 'Dice rolling is busy. Please try again later.',
    }.freeze

    attr_reader :reason

    def initialize(reason)
      @reason = reason
      super(MESSAGES.fetch(reason))
    end

    def code
      "DICE_#{reason.to_s.upcase}"
    end
  end

  ENGINE = '@dice-roller/rpg-dice-roller'
  KEYS = %w(version engine engineVersion notation total output).freeze
  ENGINE_VERSION_PATTERN = /\A\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?\z/
  COMMAND_PATTERN = %r{\A/dice(?:[[:space:]]|\z)}
  IGNORED_DEPTH_PATTERN = %r{/\*.*?\*/|\[[^\]]*\]|(?://|\#)[^\n\r\u2028\u2029]*}m
  MAX_NOTATION_BYTES = 512
  MAX_OUTPUT_BYTES = 12_288
  MAX_RESULT_BYTES = 16_384
  MAX_REPLY_BYTES = 32_768
  MAX_DEPTH = 32
  MAX_SAFE_INTEGER = (2**53) - 1
  DEFAULT_NOTATION = '1d6'
  TIMEOUT = 3
  LOCK_TTL = 10_000
  RATE_LIMIT = 10
  RATE_PERIOD = 60_000
  SLOTS = 2
  WORKER = Rails.root.join('streaming', 'chat_dice_worker.js')

  INCREMENT_SCRIPT = "local n = redis.call('INCR', KEYS[1]); if n == 1 then redis.call('PEXPIRE', KEYS[1], ARGV[1]) end; return n"
  RELEASE_SCRIPT = "if redis.call('GET', KEYS[1]) == ARGV[1] then return redis.call('DEL', KEYS[1]) end; return 0"

  class << self
    def notation(text)
      command = strip(text.to_s)
      return unless command.match?(COMMAND_PATTERN)

      strip(command[5..]).presence || DEFAULT_NOTATION
    end

    def assert_notation!(notation)
      raise Error, :limit if notation.bytesize > MAX_NOTATION_BYTES

      depth = 0
      notation.gsub(IGNORED_DEPTH_PATTERN, '').each_char do |character|
        depth += 1 if '({'.include?(character)
        depth = [depth - 1, 0].max if ')}'.include?(character)
        raise Error, :limit if depth > MAX_DEPTH
      end
    end

    def parse(value)
      return unless value.is_a?(Hash) && value.keys.map(&:to_s).sort == KEYS.sort

      value = value.transform_keys(&:to_s)
      return unless value['version'] == 1 && value['engine'] == ENGINE
      return unless value['engineVersion'].is_a?(String) && value['engineVersion'].length <= 32 && value['engineVersion'].match?(ENGINE_VERSION_PATTERN)
      return unless valid_text?(value['notation'], MAX_NOTATION_BYTES) && valid_text?(value['output'], MAX_OUTPUT_BYTES)
      return unless valid_total?(value['total'])

      result = value.slice(*KEYS)
      result.to_json.bytesize <= MAX_RESULT_BYTES ? result : nil
    end

    private

    def strip(text)
      text.gsub(/\A[[:space:]]+|[[:space:]]+\z/, '')
    end

    def valid_text?(value, max_bytes)
      value.is_a?(String) && value.present? && value.valid_encoding? && !value.include?("\0") && value.bytesize <= max_bytes
    end

    def valid_total?(value)
      (value.is_a?(Integer) || value.is_a?(Float)) && value.finite? && value.abs <= MAX_SAFE_INTEGER
    end
  end

  def roll(account, notation)
    self.class.assert_notation!(notation)

    token = SecureRandom.uuid
    user_key = "chat_dice_user:#{account.id}"
    raise Error, :busy unless redis.set(user_key, token, px: LOCK_TTL, nx: true)

    slot = nil
    begin
      raise Error, :busy if redis.eval(INCREMENT_SCRIPT, keys: ["chat_dice_rate:#{account.id}"], argv: [RATE_PERIOD]).to_i > RATE_LIMIT

      slot = Array.new(SLOTS) { |index| "chat_dice_slot:#{index}" }.find { |key| redis.set(key, token, px: LOCK_TTL, nx: true) }
      raise Error, :busy if slot.nil?

      run_worker(notation)
    ensure
      [user_key, slot].compact.each { |key| redis.eval(RELEASE_SCRIPT, keys: [key], argv: [token]) }
    end
  end

  private

  def run_worker(notation)
    Open3.popen2({ 'PATH' => ENV.fetch('PATH', '') }, node_binary, '--max-old-space-size=128', WORKER.to_s, chdir: WORKER.dirname.to_s, err: File::NULL, unsetenv_others: true) do |stdin, stdout, wait_thread|
      stdin.write(notation)
      stdin.close
      result_of(read_reply(stdout, wait_thread.pid), notation)
    end
  rescue SystemCallError, IOError
    raise Error, :busy
  end

  def read_reply(io, pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMEOUT
    buffer = +''

    loop do
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      abort_worker!(pid) if remaining <= 0 || !io.wait_readable(remaining)

      chunk = io.read_nonblock(16_384, exception: false)
      break if chunk.nil?
      next if chunk == :wait_readable

      buffer << chunk
      abort_worker!(pid) if buffer.bytesize > MAX_REPLY_BYTES
    end

    buffer
  end

  def result_of(output, notation)
    reply = JSON.parse(output)
    raise Error, :invalid unless reply.is_a?(Hash)

    result = self.class.parse(reply['result'])
    return result if result && result['notation'] == notation

    raise Error, reply['error'].in?(%w(limit busy)) ? reply['error'].to_sym : :invalid
  rescue JSON::ParserError
    raise Error, :invalid
  end

  def abort_worker!(pid)
    begin
      Process.kill('KILL', pid)
    rescue Errno::ESRCH
      nil
    end
    raise Error, :limit
  end

  def node_binary
    ENV.fetch('CHAT_DICE_NODE_BINARY', 'node')
  end
end
