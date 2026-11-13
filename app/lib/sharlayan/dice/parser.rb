# frozen_string_literal: true

class Sharlayan::Dice::Parser
  class ParseFailure < StandardError; end

  SINGLE_FUNCTIONS = %w(abs ceil cos exp floor log round sign sin sqrt tan).freeze
  DOUBLE_FUNCTIONS = %w(pow max min).freeze
  COMPARE_OPERATORS = %w(!= <= >= = <> > <).freeze
  OPERATORS = %w(** * ^ % / + -).freeze
  KEEP_DROP_NAMES = [:keep, :drop].freeze
  MAX_SAFE_NUMBER = ((2**53) - 1).to_f
  EMPTY_DESCRIPTION = /\A[\u0009-\u000d\u0020\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]*\z/

  private_constant :ParseFailure

  def initialize(notation, budget:)
    @notation = notation
    @budget = budget
    @position = 0
  end

  def parse
    invalid! unless @notation.is_a?(String) && @notation.valid_encoding?

    result = expression
    fail_parse! unless @position == @notation.length
    result
  rescue ParseFailure
    invalid!
  end

  private

  def expression
    @budget.tick!
    result = factor

    loop do
      tail = attempt do
        whitespace
        operator = read_operator
        whitespace
        [operator, *factor]
      end

      break unless tail

      result.concat(tail)
    end

    result
  end

  def factor
    @budget.tick!
    attempt { math_function } || attempt { [dice] } || attempt { [float_number] } || attempt { parenthesized } || [roll_group]
  end

  def parenthesized
    consume!('(')
    whitespace
    result = expression
    whitespace
    consume!(')')
    ['(', *result, ')']
  end

  def math_function
    function = (SINGLE_FUNCTIONS + DOUBLE_FUNCTIONS).find { |name| consume("#{name}(") }
    fail_parse! unless function

    whitespace
    result = ["#{function}(", *expression]
    whitespace

    if DOUBLE_FUNCTIONS.include?(function)
      consume!(',')
      whitespace
      result.push(',', *expression)
      whitespace
    end

    consume!(')')
    result << ')'
  end

  def dice
    @budget.tick!
    die = attempt { standard_die } || attempt { percentile_die } || fudge_die
    die[:modifiers] = modifiers
    descriptions
    die
  end

  def standard_die
    quantity = attempt { integer_or_expression }
    consume!('d')
    sides = integer_or_expression
    build_die(sides, quantity)
  end

  def percentile_die
    quantity = attempt { integer_or_expression }
    consume!('d%')
    build_die(100.0, quantity).merge(percentile: true)
  end

  def fudge_die
    quantity = attempt { integer_or_expression }
    consume!('dF')
    sides = attempt do
      consume!('.')
      number = read_pattern(/[12]/)
      fail_parse! unless number
      number.to_i
    end

    build_die(sides || 2, quantity, fudge: sides || 2)
  end

  def build_die(sides, quantity, fudge: nil)
    quantity = 1.0 if quantity.nil? || quantity.zero? || (quantity.respond_to?(:nan?) && quantity.nan?)
    invalid! unless real_number?(sides) && sides >= 1 && sides <= MAX_SAFE_NUMBER
    invalid! unless real_number?(quantity) && quantity >= 1 && quantity <= 999

    { type: :dice, quantity: quantity.to_i, sides: sides, fudge: fudge }
  end

  def real_number?(value)
    (value.is_a?(Integer) || value.is_a?(Float)) && value.finite?
  end

  def roll_group
    @budget.tick!
    consume!('{')
    whitespace
    expressions = [expression]

    loop do
      item = attempt do
        whitespace
        consume!(',')
        whitespace
        expression
      end

      break unless item

      expressions << item
    end

    whitespace
    consume!('}')
    parsed_modifiers = modifiers
    descriptions
    invalid! if expressions.any? { |item| item.any? { |token| token.is_a?(Hash) && token[:type] == :group } }

    { type: :group, expressions: expressions, modifiers: parsed_modifiers }
  end

  def integer_or_expression
    @budget.tick!
    integer_number || quantity_expression
  end

  def quantity_expression
    initial_position = @position
    consume!('(')
    whitespace
    float_number
    tail_count = 0

    loop do
      tail = attempt do
        whitespace
        read_operator
        whitespace
        float_number
      end

      break unless tail

      tail_count += 1
    end

    fail_parse! if tail_count.zero?
    whitespace
    consume!(')')
    source = @notation[initial_position...@position]
    invalid! if source.include?('**')
    Sharlayan::Dice::Arithmetic.evaluate([source.delete(" \t\n\r")], budget: @budget)
  end

  def integer_number
    number = read_pattern(/[1-9][0-9]*/)
    number&.to_f
  end

  def float_number
    number = read_pattern(/-?[0-9]+(?:\.[0-9]+)?/)
    fail_parse! unless number
    number.to_f
  end

  def read_operator
    value = OPERATORS.find { |operator| consume(operator) }
    fail_parse! unless value
    value == '**' ? '^' : value
  end

  def modifiers
    result = {}

    while (modifier = attempt { read_modifier })
      key = [modifier[:name]]
      key << modifier[:end] if KEEP_DROP_NAMES.include?(modifier[:name])
      result[key] = modifier
    end

    result.values
  end

  def read_modifier
    @budget.tick!
    attempt { explode_modifier } || attempt { target_modifier } ||
      attempt { keep_drop_modifier('d', :drop, :l) } || attempt { keep_drop_modifier('k', :keep, :h) } ||
      attempt { repeated_modifier('r', :reroll) } || attempt { repeated_modifier('u', :unique) } ||
      attempt { comparison_modifier('cs', :critical_success) } || attempt { comparison_modifier('cf', :critical_failure) } ||
      attempt { sorting_modifier } || attempt { range_modifier('max', :max) } || range_modifier('min', :min)
  end

  def explode_modifier
    consume!('!')
    compound = consume('!')
    penetrate = consume('p')
    { name: :explode, compound: compound, penetrate: penetrate, compare: attempt { comparison } }
  end

  def target_modifier
    success = comparison
    failure = attempt do
      consume!('f')
      comparison
    end

    { name: :target, compare: success, failure: failure }
  end

  def keep_drop_modifier(prefix, name, default_end)
    consume!(prefix)
    ending = read_pattern(/[lh]/)
    quantity = integer_number
    fail_parse! unless quantity
    invalid! unless quantity.finite?
    { name: name, end: ending ? ending.to_sym : default_end, quantity: quantity.to_i }
  end

  def repeated_modifier(prefix, name)
    consume!(prefix)
    once = consume('o')
    { name: name, once: once, compare: attempt { comparison } }
  end

  def comparison_modifier(prefix, name)
    consume!(prefix)
    { name: name, compare: attempt { comparison } }
  end

  def sorting_modifier
    consume!('s')
    direction = read_pattern(/[ad]/)
    { name: :sort, direction: direction ? direction.to_sym : :a }
  end

  def range_modifier(prefix, name)
    consume!(prefix)
    value = float_number
    invalid! unless value.finite?
    { name: name, value: value }
  end

  def comparison
    operator = COMPARE_OPERATORS.find { |value| consume(value) }
    fail_parse! unless operator
    value = float_number
    invalid! unless value.finite?
    [operator, value]
  end

  def descriptions
    loop do
      whitespace
      break unless attempt { comment }
    end
  end

  def comment
    @budget.tick!
    text = if consume('/*')
             read_comment_until('*/')
           elsif consume('[')
             read_comment_until(']')
           elsif consume('//') || consume('#')
             read_pattern(/[^\n\r\u2028\u2029]*/) || ''
           else
             fail_parse!
           end

    invalid! if text.match?(EMPTY_DESCRIPTION)
    true
  end

  def read_comment_until(ending)
    finish = @notation.index(ending, @position)
    fail_parse! unless finish
    text = @notation[@position...finish]
    @position = finish + ending.length
    text
  end

  def whitespace
    read_pattern(/[ \t\n\r]*/)
  end

  def read_pattern(pattern)
    @budget.tick!
    match = pattern.match(@notation, @position)
    return unless match && match.begin(0) == @position

    @position = match.end(0)
    match[0]
  end

  def consume(text)
    @budget.tick!
    return false unless @notation[@position, text.length] == text

    @position += text.length
    true
  end

  def consume!(text)
    fail_parse! unless consume(text)
  end

  def attempt
    initial_position = @position
    yield
  rescue ParseFailure
    @position = initial_position
    nil
  end

  def fail_parse!
    raise ParseFailure
  end

  def invalid!
    raise Sharlayan::Dice::Error, :invalid
  end
end
