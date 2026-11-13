# frozen_string_literal: true

require 'securerandom'

class Sharlayan::Dice
  class Error < StandardError
    attr_reader :reason

    def initialize(reason)
      @reason = reason
      super(reason.to_s)
    end
  end

  ENGINE = '@dice-roller/rpg-dice-roller'
  ENGINE_VERSION = '5.5.1'
  MAX_NOTATION_BYTES = 512
  MAX_OUTPUT_BYTES = 12_288
  MAX_RESULT_BYTES = 16_384
  MAX_DEPTH = 32
  MAX_SAFE_INTEGER = (2**53) - 1
  IGNORED_DEPTH_PATTERN = %r{/\*.*?\*/|\[[^\]]*\]|(?://|\#)[^\n\r\u2028\u2029]*}m

  def initialize(notation, random: SecureRandom, budget: Budget.new)
    @notation = notation
    @random = random
    @budget = budget
  end

  def roll
    validate_notation!
    tokens = Parser.new(@notation, budget: @budget).parse
    result = Evaluator.new(budget: @budget, random: @random).call(tokens)
    total = Arithmetic.total(result.fetch(:total))
    raise Error, :limit unless total.finite? && total.abs <= MAX_SAFE_INTEGER

    output = "#{@notation}: #{result.fetch(:output)} = #{Arithmetic.format(total)}"
    raise Error, :limit if output.bytesize > MAX_OUTPUT_BYTES

    @budget.tick!
    { 'version' => 1, 'engine' => ENGINE, 'engineVersion' => ENGINE_VERSION, 'notation' => @notation, 'total' => total, 'output' => output }
  end

  private

  def validate_notation!
    raise Error, :invalid unless @notation.is_a?(String) && @notation.valid_encoding? && !@notation.include?("\0")
    raise Error, :limit if @notation.bytesize > MAX_NOTATION_BYTES

    depth = 0
    @notation.gsub(IGNORED_DEPTH_PATTERN, '').each_char do |character|
      depth += 1 if '({'.include?(character)
      depth = [depth - 1, 0].max if ')}'.include?(character)
      raise Error, :limit if depth > MAX_DEPTH
    end
  end
end
