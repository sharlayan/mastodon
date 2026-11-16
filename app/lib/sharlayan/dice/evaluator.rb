# frozen_string_literal: true

require 'securerandom'

class Sharlayan::Dice::Evaluator
  MODIFIER_ORDER = {
    min: 1,
    max: 2,
    explode: 3,
    reroll: 4,
    unique: 5,
    keep: 6,
    drop: 7,
    target: 8,
    critical_success: 9,
    critical_failure: 10,
    sort: 11,
  }.freeze

  GROUP_MODIFIERS = %i(keep drop target sort).freeze

  FLAGS = {
    compound: '!',
    explode: '!',
    critical_failure: '__',
    critical_success: '**',
    drop: 'd',
    max: 'v',
    min: '^',
    penetrate: 'p',
    reroll: 'r',
    reroll_once: 'ro',
    target_failure: '_',
    target_success: '*',
    unique: 'u',
    unique_once: 'uo',
  }.freeze

  class Result
    attr_accessor :value, :calculation_value, :use_in_total, :flags

    def initialize(value)
      @value = value
      @calculation_value = nil
      @use_in_total = true
      @flags = []
    end

    def flag(name)
      flags << name unless flags.include?(name)
    end

    def calculation
      calculation_value.nil? ? value : calculation_value
    end

    def modifier_flags
      flags.map { |name| FLAGS.fetch(name) }.join
    end

    def output
      Sharlayan::Dice::Arithmetic.format(value) + modifier_flags
    end
  end

  class Rolls
    attr_accessor :rolls

    def initialize(rolls, evaluator)
      @rolls = rolls
      @evaluator = evaluator
    end

    def value
      rolls.reduce(0.0) do |total, roll|
        @evaluator.tick!
        total + (roll.use_in_total ? roll.calculation : 0)
      end
    end

    def output
      "[#{rolls.map(&:output).join(', ')}]"
    end
  end

  class Group < Result
    attr_accessor :results

    def initialize(results, evaluator, roll_group: false)
      super(nil)
      @results = results
      @evaluator = evaluator
      @roll_group = roll_group
    end

    def value
      value = results.first.is_a?(String) ? '' : 0.0
      results.each do |result|
        @evaluator.tick!
        operand = case result
                  when Group
                    result.use_in_total ? result.calculation : 0.0
                  when Rolls
                    result.value
                  else
                    result
                  end

        value = if value.is_a?(String) || operand.is_a?(String) || operand.is_a?(Complex)
                  text(value) + text(operand)
                else
                  value + operand
                end
      end

      value.is_a?(String) ? @evaluator.calculate([value]) : value
    end

    def output
      contents = results.map do |result|
        if result.is_a?(Numeric)
          Sharlayan::Dice::Arithmetic.format(result)
        elsif result.respond_to?(:output)
          result.output
        else
          result
        end
      end.join(@roll_group ? ', ' : '')
      contents = "{#{contents}}" if @roll_group
      modifier_flags.empty? ? contents : "(#{contents})#{modifier_flags}"
    end

    private

    def text(value)
      value.is_a?(String) ? value : Sharlayan::Dice::Arithmetic.format(value)
    end
  end

  def initialize(budget:, random: SecureRandom)
    @budget = budget
    @random = random
  end

  def call(tokens)
    result = expression(tokens)
    { total: result.value, output: result.output }
  end

  def tick!
    @budget.tick!
  end

  def calculate(tokens)
    Sharlayan::Dice::Arithmetic.evaluate(tokens, budget: @budget)
  end

  private

  def expression(tokens)
    results = tokens.map do |token|
      tick!
      next token unless token.is_a?(Hash)

      case token.fetch(:type)
      when :dice
        dice(token)
      when :group
        group(token)
      else
        raise Sharlayan::Dice::Error, :invalid
      end
    end

    Group.new(results, self)
  end

  def dice(definition)
    rolls = Rolls.new(Array.new(definition.fetch(:quantity)) do
      tick!
      roll_once(definition)
    end, self)
    apply_modifiers(rolls, definition)
  end

  def group(definition)
    results = definition.fetch(:expressions).map { |tokens| expression(tokens) }
    apply_modifiers(Group.new(results, self, roll_group: true), definition)
  end

  def roll_once(definition)
    value = case definition[:fudge]
            when 1
              roll = integer(1, 6)
              case roll
              when 1 then -1
              when 6 then 1
              else 0
              end
            when 2
              integer(1, 3) - 2
            else
              integer(1, definition.fetch(:sides))
            end
    Result.new(value)
  end

  def integer(minimum, maximum)
    minimum = minimum.floor
    maximum = maximum.floor
    return minimum if minimum == maximum

    @budget.draw!
    minimum + @random.random_number(maximum - minimum + 1)
  rescue SystemCallError, IOError, NotImplementedError
    raise Sharlayan::Dice::Error, :busy
  end

  def apply_modifiers(results, definition)
    definition.fetch(:modifiers).sort_by { |modifier| MODIFIER_ORDER.fetch(modifier.fetch(:name)) }.each do |modifier|
      tick!
      name = modifier.fetch(:name)
      raise Sharlayan::Dice::Error, :invalid if results.is_a?(Group) && !GROUP_MODIFIERS.include?(name)

      case name
      when :min, :max
        clamp(results, modifier)
      when :explode
        explode(results, definition, modifier)
      when :reroll, :unique
        reroll(results, definition, modifier)
      when :keep, :drop
        keep_or_drop(results, modifier)
      when :target
        target(results, modifier)
      when :critical_success, :critical_failure
        critical(results, definition, modifier)
      when :sort
        sort(results, modifier)
      end
    end
    results
  end

  def clamp(results, modifier)
    name = modifier.fetch(:name)
    boundary = modifier.fetch(:value)
    results.rolls.each do |roll|
      tick!
      next unless name == :min ? roll.value < boundary : roll.value > boundary

      roll.value = boundary
      roll.flag(name)
    end
  end

  def explode(results, definition, modifier)
    assert_repeatable!(definition)
    comparison = modifier[:compare] || ['=', maximum(definition)]
    results.rolls = results.rolls.flat_map do |roll|
      tick!
      sub_rolls = [roll]
      compare_value = roll.value

      1000.times do
        tick!
        break unless matches?(compare_value, comparison)

        previous = sub_rolls.last
        next_roll = roll_once(definition)
        compare_value = next_roll.value
        previous.flag(:explode)
        if modifier[:penetrate]
          previous.flag(:penetrate)
          next_roll.value -= 1
        end
        sub_rolls << next_roll
      end

      if modifier[:compound] && sub_rolls.length > 1
        value = 0.0
        sub_rolls.each do |result|
          tick!
          value += result.value
        end
        roll.value = value
        roll.flags = %i(explode compound)
        roll.flag(:penetrate) if modifier[:penetrate]
        [roll]
      else
        sub_rolls
      end
    end
  end

  def reroll(results, definition, modifier)
    assert_repeatable!(definition)
    unique = modifier.fetch(:name) == :unique
    comparison = modifier[:compare] || (unique ? nil : ['=', minimum(definition)])
    previous_values = {}

    results.rolls.each_with_index do |roll, index|
      tick!
      unless unique && index.zero?
        1000.times do
          tick!
          break if comparison && !matches?(roll.value, comparison)
          break if unique && !previous_values.key?(roll.value.to_f)

          roll.value = roll_once(definition).value
          roll.flag(reroll_flag(unique, modifier[:once]))
          break if modifier[:once]
        end
      end
      previous_values[roll.value.to_f] = true if unique
    end
  end

  def reroll_flag(unique, once)
    if unique
      once ? :unique_once : :unique
    else
      once ? :reroll_once : :reroll
    end
  end

  def keep_or_drop(results, modifier)
    rolls = if results.is_a?(Rolls)
              results.rolls
            elsif results.results.length == 1 && results.results.first.is_a?(Group)
              results.results.first.results.grep(Rolls).flat_map(&:rolls)
            else
              results.results
            end

    ordered = sorted(rolls)
    quantity = modifier.fetch(:quantity)
    high = modifier.fetch(:end) == :h
    from, to = if modifier.fetch(:name) == :keep
                 high ? [0, ordered.length - quantity] : [quantity, ordered.length]
               else
                 high ? [ordered.length - quantity, ordered.length] : [0, quantity]
               end

    from = slice_index(from, ordered.length)
    to = slice_index(to, ordered.length)
    ordered[from...[from, to].max].each do |roll|
      tick!
      roll.flag(:drop)
      roll.use_in_total = false
    end
  end

  def slice_index(index, length)
    index.negative? ? [length + index, 0].max : [index, length].min
  end

  def target(results, modifier)
    rolls = results.is_a?(Group) ? results.results : results.rolls
    rolls.each do |roll|
      tick!
      if matches?(roll.value, modifier.fetch(:compare))
        roll.flag(:target_success)
        roll.calculation_value = 1
      elsif modifier[:failure] && matches?(roll.value, modifier[:failure])
        roll.flag(:target_failure)
        roll.calculation_value = -1
      else
        roll.calculation_value = 0
      end
    end
  end

  def critical(results, definition, modifier)
    name = modifier.fetch(:name)
    comparison = modifier[:compare] || ['=', name == :critical_success ? maximum(definition) : minimum(definition)]
    results.rolls.each do |roll|
      tick!
      roll.flag(name) if matches?(roll.value, comparison)
    end
  end

  def sort(results, modifier)
    rolls = results.is_a?(Group) ? results.results : results.rolls
    direction = modifier.fetch(:direction) == :d ? -1 : 1
    ordered = sorted(rolls, direction)

    if results.is_a?(Group)
      results.results = ordered
      ordered.each { |result| sort(result, modifier) if result.is_a?(Group) || result.is_a?(Rolls) }
    else
      results.rolls = ordered
    end
  end

  def sorted(rolls, direction = 1)
    values = {}.compare_by_identity
    Sharlayan::Dice::StableSort.new(rolls) do |left, right|
      tick!
      left_value = values.fetch(left) { values[left] = numeric(left.value) if left.respond_to?(:value) }
      right_value = values.fetch(right) { values[right] = numeric(right.value) if right.respond_to?(:value) }
      comparison = left_value && right_value ? left_value <=> right_value : 0
      (comparison || 0) * direction
    end.call
  end

  def minimum(definition)
    definition[:fudge] ? -1 : 1
  end

  def maximum(definition)
    definition[:fudge] ? 1 : definition.fetch(:sides)
  end

  def assert_repeatable!(definition)
    raise Sharlayan::Dice::Error, :invalid if minimum(definition) == maximum(definition)
  end

  def matches?(value, comparison)
    value = numeric(value)
    return false unless value.is_a?(Integer) || value.is_a?(Float)
    return false if value.respond_to?(:nan?) && value.nan?

    operator, target = comparison
    case operator
    when '=' then value == target
    when '!=', '<>' then value != target
    when '<' then value < target
    when '>' then value > target
    when '<=' then value <= target
    when '>=' then value >= target
    else raise Sharlayan::Dice::Error, :invalid
    end
  end

  def numeric(value)
    value.is_a?(Complex) ? Float(Sharlayan::Dice::Arithmetic.format(value), exception: false) : value
  end
end
