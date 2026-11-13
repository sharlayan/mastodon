# frozen_string_literal: true

require 'strscan'
require_relative 'numeric_math'

class Sharlayan::Dice::Arithmetic
  FUNCTIONS = %w(abs ceil cos exp floor log round sign sin sqrt tan pow max min).freeze
  EXPLICIT_OPERATORS = %w(* / %).freeze
  ADDITIVE_OPERATORS = %w(+ -).freeze
  DIVISION_CONSTANTS = [:constant, :unary_constant].freeze
  PORTED_FUNCTIONS = [:sin, :cos, :tan, :exp].freeze
  Value = Struct.new(:number, :kind, :percentage)

  class << self
    def evaluate(tokens, budget:)
      new(tokens, budget: budget).evaluate
    end

    def format(number)
      return format_complex(number) if number.is_a?(Complex)
      return '0' if number.zero?
      return number.to_s unless number.finite?

      string = number.to_f.to_s
      mantissa, exponent = string.split('e')
      return mantissa.delete_suffix('.0') unless exponent

      exponent = exponent.to_i
      return "#{mantissa.delete_suffix('.0')}e#{'+' unless exponent.negative?}#{exponent}" unless exponent.between?(-6, 20)

      sign = mantissa.start_with?('-') ? '-' : ''
      digits = mantissa.delete('-.')
      position = exponent + 1
      string = if position <= 0
                 "0.#{'0' * -position}#{digits}"
               elsif position >= digits.length
                 digits.ljust(position, '0')
               else
                 "#{digits[0...position]}.#{digits[position..]}"
               end
      string = string.sub(/0+\z/, '').delete_suffix('.') if string.include?('.')
      sign + string
    end

    def total(value)
      text = format(value)
      prefix = text[/\A[+-]?(?:Infinity|\d+(?:\.\d*)?(?:e[+-]?\d+)?)/i]
      return 0.0 unless prefix

      number = if prefix.include?('Infinity')
                 prefix.start_with?('-') ? -Float::INFINITY : Float::INFINITY
               else
                 prefix.to_f
               end
      return number unless number.finite? && number.abs < 1e21

      rounded = decimal_float(((number.abs.to_r * 100) + Rational(1, 2)).floor, 2)
      number.negative? ? -rounded : rounded
    end

    private

    def decimal_float(integer, places)
      whole, fraction = integer.abs.divmod(10**places)
      number = "#{whole}.#{fraction.to_s.rjust(places, '0')}".to_f
      integer.negative? ? -number : number
    end

    def format_complex(number)
      return 'NaN' if number.real.to_f.nan? || number.imaginary.to_f.nan?
      return 'Infinity' unless number.finite?

      real = number.real.abs < 1e-15 ? 0 : number.real
      imaginary = number.imaginary.abs < 1e-15 ? 0 : number.imaginary
      return format(real) if imaginary.zero?

      suffix = "#{format(imaginary.abs) unless imaginary.abs == 1}i"
      return "#{'-' if imaginary.negative?}#{suffix}" if real.zero?

      "#{format(real)} #{imaginary.negative? ? '-' : '+'} #{suffix}"
    end
  end

  def initialize(tokens, budget:)
    @scanner = StringScanner.new(tokens.map { |token| token.is_a?(Numeric) ? self.class.format(token) : token }.join)
    @budget = budget
    advance
  end

  def evaluate
    value = expression.number
    raise Sharlayan::Dice::Error, :invalid unless @token.nil?

    value
  rescue ArgumentError, TypeError, ZeroDivisionError
    raise Sharlayan::Dice::Error, :invalid
  end

  private

  def advance
    @budget.tick!
    @scanner.skip(/\s*/)
    @token = if @scanner.eos?
               nil
             elsif (number = @scanner.scan(/(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?/i))
               number.to_f
             elsif (word = @scanner.scan(/[a-zA-Z][a-zA-Z0-9_]*/))
               word
             else
               @scanner.getch
             end
  end

  def expression
    value = explicit_expression
    while ADDITIVE_OPERATORS.include?(@token)
      operator = @token
      advance
      right = explicit_expression
      right = Value.new(calculate('*', value.number, right.number)) if right.percentage
      value = Value.new(calculate(operator, value.number, right.number), :operator)
    end
    value
  end

  def explicit_expression
    value = implicit_expression
    while EXPLICIT_OPERATORS.include?(@token)
      operator = @token
      advance
      if operator == '%' && !@token.is_a?(Numeric) && @token != '(' && !symbol?(@token)
        value = Value.new(calculate('/', value.number, 100.0), :operator, true)
      else
        right = implicit_expression
        value = Value.new(calculate(operator, value.number, right.number), :operator)
      end
    end
    value
  end

  def implicit_expression
    value = division_expression
    last = value
    while symbol?(@token) || @token == '(' || (@token.is_a?(Numeric) && last.kind == :other)
      last = division_expression
      value = Value.new(calculate('*', value.number, last.number), :operator)
    end
    value
  end

  def division_expression
    value = unary_expression
    last = value
    while @token == '/' && DIVISION_CONSTANTS.include?(last.kind) && numeric_symbol_division?
      advance
      last = unary_expression
      value = Value.new(calculate('/', value.number, last.number), :operator)
    end
    value
  end

  def numeric_symbol_division?
    position = @scanner.pos
    token = @token
    advance
    return false unless @token.is_a?(Numeric)

    advance
    symbol?(@token) || @token == '('
  ensure
    @scanner.pos = position
    @token = token
  end

  def unary_expression
    return power_expression unless ADDITIVE_OPERATORS.include?(@token)

    operator = @token
    advance
    value = unary_expression
    Value.new(operator == '-' ? -value.number : value.number, value.kind == :constant ? :unary_constant : :operator)
  end

  def power_expression
    value = factor
    if @token == '^'
      advance
      value = Value.new(calculate('^', value.number, unary_expression.number), :operator)
    end
    value
  end

  def factor
    token = @token
    advance
    case token
    when Numeric
      Value.new(token, :constant)
    when '('
      value = expression
      consume(')')
      Value.new(value.number, :other)
    when 'Infinity'
      Value.new(Float::INFINITY, :other)
    when 'NaN'
      Value.new(Float::NAN, :other)
    when 'i'
      Value.new(Complex(0.0, 1.0), :other)
    else
      raise Sharlayan::Dice::Error, :invalid unless FUNCTIONS.include?(token)

      consume('(')
      arguments = [expression.number]
      if %w(pow max min).include?(token)
        consume(',')
        arguments << expression.number
      end
      consume(')')
      Value.new(function(token, arguments), :other)
    end
  end

  def symbol?(token)
    token.is_a?(String) && token.match?(/\A[a-zA-Z]/)
  end

  def consume(token)
    raise Sharlayan::Dice::Error, :invalid unless @token == token

    advance
  end

  def calculate(operator, left, right)
    @budget.tick!
    return complex_calculate(operator, complex_number(left), complex_number(right)) if left.is_a?(Complex) || right.is_a?(Complex)

    case operator
    when '+' then left + right
    when '-' then left - right
    when '*' then left * right
    when '/' then left / right
    when '^' then power(left, right)
    when '%'
      right.zero? ? left : left - (right * rounded_integer(left / right, :floor))
    end
  end

  def function(name, arguments)
    value = arguments.first
    case name
    when 'abs' then value.is_a?(Complex) ? complex_hypot(value.real, value.imaginary) : value.abs
    when 'pow' then calculate('^', *arguments)
    when 'max', 'min' then extreme(arguments, name)
    when 'round', 'ceil', 'floor' then rounded_integer(value, name.to_sym)
    when 'sign' then sign(value)
    when 'sqrt' then square_root(value)
    when 'log' then logarithm(value)
    when 'exp' then exponential(value)
    when 'sin', 'cos', 'tan' then trigonometric(name, value)
    end
  end

  def extreme(arguments, name)
    arguments.reduce do |result, value|
      next value if number_nan?(value)
      raise Sharlayan::Dice::Error, :invalid if result.is_a?(Complex) || value.is_a?(Complex)

      replace = name == 'max' ? value > result : value < result
      replace && !nearly_equal?(value, result) ? value : result
    end
  end

  def sign(value)
    if value.is_a?(Complex)
      return Complex(sign(value.real), 0.0) if value.imaginary.zero?

      absolute = complex_hypot(value.real, value.imaginary)
      return Complex(value.real / absolute, value.imaginary / absolute)
    end

    if value.zero? || value.nan?
      value
    else
      value.positive? ? 1.0 : -1.0
    end
  end

  def power(left, right)
    return 0.0 if (left * left < 1 && right == Float::INFINITY) || (left * left > 1 && right == -Float::INFINITY)
    return real_power(left, right) if left >= 0 || (right.finite? && right == right.truncate)

    complex_power(Complex(left, 0.0), Complex(right, 0.0))
  end

  def complex_calculate(operator, left, right)
    left_infinite = !left.finite?
    right_infinite = !right.finite?
    case operator
    when '+', '-'
      return complex_nan if left_infinite && right_infinite
      return complex_infinity if left_infinite || right_infinite

      operator == '+' ? Complex(left.real + right.real, left.imaginary + right.imaginary) : Complex(left.real - right.real, left.imaginary - right.imaginary)
    when '*'
      return complex_nan if (left_infinite && right.zero?) || (right_infinite && left.zero?)
      return complex_infinity if left_infinite || right_infinite
      return Complex(left.real * right.real, 0.0) if left.imaginary.zero? && right.imaginary.zero?

      Complex((left.real * right.real) - (left.imaginary * right.imaginary), (left.real * right.imaginary) + (left.imaginary * right.real))
    when '/'
      complex_divide(left, right, left_infinite, right_infinite)
    when '^'
      complex_power(left, right)
    else
      raise Sharlayan::Dice::Error, :invalid
    end
  end

  def complex_divide(left, right, left_infinite, right_infinite)
    return complex_nan if (left.zero? && right.zero?) || (left_infinite && right_infinite)
    return complex_infinity if right.zero? || left_infinite
    return Complex(0.0, 0.0) if left.zero? || right_infinite
    return Complex(left.real / right.real, left.imaginary / right.real) if right.imaginary.zero?

    if right.real.abs < right.imaginary.abs
      ratio = right.real / right.imaginary
      divisor = (right.real * ratio) + right.imaginary
      Complex(((left.real * ratio) + left.imaginary) / divisor, ((left.imaginary * ratio) - left.real) / divisor)
    else
      ratio = right.imaginary / right.real
      divisor = (right.imaginary * ratio) + right.real
      Complex((left.real + (left.imaginary * ratio)) / divisor, (left.imaginary - (left.real * ratio)) / divisor)
    end
  end

  def complex_power(left, right)
    return Complex(1.0, 0.0) if right.zero?

    if right.imaginary.zero?
      return Complex(real_power(left.real, right.real), 0.0) if left.imaginary.zero? && left.real.positive?

      if left.real.zero? && right.real.finite?
        quadrant = (right.real.remainder(4) + 4).remainder(4)
        magnitude = real_power(left.imaginary, right.real)
        case quadrant
        when 0 then return Complex(magnitude, 0.0)
        when 1 then return Complex(0.0, magnitude)
        when 2 then return Complex(-magnitude, 0.0)
        when 3 then return Complex(0.0, -magnitude)
        end
      end
    end

    return Complex(0.0, 0.0) if left.zero? && right.real.positive?

    argument = Math.atan2(left.imaginary, left.real)
    logarithm = complex_log_hypot(left.real, left.imaginary)
    magnitude = safe_math(:exp, (right.real * logarithm) - (right.imaginary * argument))
    angle = (right.imaginary * logarithm) + (right.real * argument)
    Complex(magnitude * safe_math(:cos, angle), magnitude * safe_math(:sin, angle))
  end

  def real_power(left, right)
    return 1.0 if right.zero?
    return Float::NAN if left.nan? || right.nan? || (left.abs == 1 && right.infinite?)
    return Float::NAN if left.negative? && right.finite? && right != right.truncate

    left**right
  end

  def square_root(value)
    return safe_math(:sqrt, value) unless value.is_a?(Complex) || value.negative?

    value = complex_number(value)
    real = value.real
    imaginary = value.imaginary
    return real >= 0 ? Complex(safe_math(:sqrt, real), 0.0) : Complex(0.0, safe_math(:sqrt, -real)) if imaginary.zero?

    absolute = complex_hypot(real, imaginary)
    root_real = safe_math(:sqrt, 0.5 * (absolute + real.abs))
    root_imaginary = imaginary.abs / (2 * root_real)
    if real >= 0
      Complex(root_real, imaginary.negative? ? -root_imaginary : root_imaginary)
    else
      Complex(root_imaginary, imaginary.negative? ? -root_real : root_real)
    end
  end

  def logarithm(value)
    return safe_math(:log, value) unless value.is_a?(Complex) || value.negative? || value.nan?

    value = complex_number(value)
    Complex(complex_log_hypot(value.real, value.imaginary), Math.atan2(value.imaginary, value.real))
  end

  def exponential(value)
    return safe_math(:exp, value) unless value.is_a?(Complex)

    magnitude = safe_math(:exp, value.real)
    return Complex(magnitude, 0.0) if value.imaginary.zero?

    Complex(magnitude * safe_math(:cos, value.imaginary), magnitude * safe_math(:sin, value.imaginary))
  end

  def trigonometric(name, value)
    return safe_math(name.to_sym, value) unless value.is_a?(Complex)

    real = value.real
    imaginary = value.imaginary
    case name
    when 'sin' then Complex(safe_math(:sin, real) * safe_math(:cosh, imaginary), safe_math(:cos, real) * safe_math(:sinh, imaginary))
    when 'cos' then Complex(safe_math(:cos, real) * safe_math(:cosh, imaginary), -safe_math(:sin, real) * safe_math(:sinh, imaginary))
    when 'tan'
      divisor = safe_math(:cos, 2 * real) + safe_math(:cosh, 2 * imaginary)
      Complex(safe_math(:sin, 2 * real) / divisor, safe_math(:sinh, 2 * imaginary) / divisor)
    end
  end

  def complex_hypot(real, imaginary)
    real = real.abs
    imaginary = imaginary.abs
    real, imaginary = imaginary, real if real < imaginary
    return safe_math(:sqrt, (real * real) + (imaginary * imaginary)) if real < 1e8

    ratio = imaginary / real
    real * safe_math(:sqrt, 1 + (ratio * ratio))
  end

  def complex_log_hypot(real, imaginary)
    return safe_math(:log, imaginary.abs) if real.zero?
    return safe_math(:log, real.abs) if imaginary.zero?
    return 0.5 * safe_math(:log, (real * real) + (imaginary * imaginary)) if real.abs < 3000 && imaginary.abs < 3000

    real *= 0.5
    imaginary *= 0.5
    (0.5 * safe_math(:log, (real * real) + (imaginary * imaginary))) + Math.log(2)
  end

  def complex_infinity
    Complex(Float::INFINITY, Float::INFINITY)
  end

  def complex_nan
    Complex(Float::NAN, Float::NAN)
  end

  def complex_number(value)
    Complex(value.real.to_f, value.imaginary.to_f)
  end

  def number_nan?(value)
    value.is_a?(Complex) ? value.real.nan? || value.imaginary.nan? : value.nan?
  end

  def safe_math(name, value)
    return Sharlayan::Dice::NumericMath.public_send(name, value) if PORTED_FUNCTIONS.include?(name)

    Math.public_send(name, value)
  rescue Math::DomainError
    Float::NAN
  end

  def rounded_integer(value, method)
    return Complex(native_integer(value.real, method), native_integer(value.imaginary, method)) if value.is_a?(Complex)
    return value unless value.finite?

    precise = decimal_round(value, 12)
    rounded = decimal_round(nearly_equal?(value, precise) ? precise : value, 0)
    return rounded if method == :round

    result = native_integer(value, method)
    nearly_equal?(value, rounded) && !nearly_equal?(value, result) ? rounded : result
  end

  def decimal_round(value, places)
    scale = 10**places
    result = ((Rational(self.class.format(value)).abs * scale) + Rational(1, 2)).floor
    rounded = self.class.send(:decimal_float, result, places)
    negative_number?(value) ? -rounded : rounded
  end

  def native_integer(value, method)
    return value unless value.finite? && !value.zero?

    result = if method == :round
               floor = value.floor.to_f
               value - floor < 0.5 ? floor : floor + 1
             else
               value.public_send(method).to_f
             end
    result.zero? && value.negative? ? -0.0 : result
  end

  def negative_number?(value)
    value.negative? || (value.zero? && (1.0 / value).negative?)
  end

  def nearly_equal?(left, right)
    return false if left.nan? || right.nan?
    return left == right unless left.finite? && right.finite?

    (left - right).abs <= [1e-15, 1e-12 * [left.abs, right.abs].max].max
  end
end
