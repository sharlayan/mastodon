# frozen_string_literal: true

class Sharlayan::Dice::NumericMath
  TWO_OVER_PI = [
    0xA2F983, 0x6E4E44, 0x1529FC, 0x2757D1, 0xF534DD, 0xC0DB62, 0x95993C,
    0x439041, 0xFE5163, 0xABDEBB, 0xC561B7, 0x246E3A, 0x424DD2, 0xE00649,
    0x2EEA09, 0xD1921C, 0xFE1DEB, 0x1CB129, 0xA73EE8, 0x8235F5, 0x2EBB44,
    0x84E99C, 0x7026B4, 0x5F7E41, 0x3991D6, 0x398353, 0x39F49C, 0x845F8B,
    0xBDF928, 0x3B1FF8, 0x97FFDE, 0x05980F, 0xEF2F11, 0x8B5A0A, 0x6D1F6D,
    0x367ECF, 0x27CB09, 0xB74F46, 0x3F669E, 0x5FEA2D, 0x7527BA, 0xC7EBE5,
    0xF17B3D, 0x0739F7, 0x8A5292, 0xEA6BFB, 0x5FB11F, 0x8D5D08, 0x560330,
    0x46FC7B, 0x6BABF0, 0xCFBC20, 0x9AF436, 0x1DA9E3, 0x91615E, 0xE61B08,
    0x659985, 0x5F14A0, 0x68408D, 0xFFD880, 0x4D7327, 0x310606, 0x1556CA,
    0x73A8C9, 0x60E27B, 0xC08C6B
  ].freeze
  PIO2_HIGH_WORDS = [
    0x3FF921FB, 0x400921FB, 0x4012D97C, 0x401921FB, 0x401F6A7A, 0x4022D97C, 0x4025FDBB,
    0x402921FB, 0x402C463A, 0x402F6A7A, 0x4031475C, 0x4032D97C, 0x40346B9C, 0x4035FDBB,
    0x40378FDB, 0x403921FB, 0x403AB41B, 0x403C463A, 0x403DD85A, 0x403F6A7A, 0x40407E4C,
    0x4041475C, 0x4042106C, 0x4042D97C, 0x4043A28C, 0x40446B9C, 0x404534AC, 0x4045FDBB,
    0x4046C6CB, 0x40478FDB, 0x404858EB, 0x404921FB
  ].freeze
  PIO2 = [1.57079632673412561417, 6.07710050650619224932e-11, 6.07710050630396597660e-11, 2.02226624879595063154e-21, 2.02226624871116645580e-21, 8.47842766036889956997e-32].freeze
  TAN_COEFFICIENTS = [
    3.33333333333334091986e-01,
    1.33333333333201242699e-01,
    5.39682539762260521377e-02,
    2.18694882948595424599e-02,
    8.86323982359930005737e-03,
    3.59207910759131235356e-03,
    1.45620945432529025516e-03,
    5.88041240820264096874e-04,
    2.46463134818469906812e-04,
    7.81794442939557092300e-05,
    7.14072491382608190305e-05,
    -1.85586374855275456654e-05,
    2.59073051863633712884e-05,
  ].freeze
  TWO_OVER_PI_RATIO = Rational(TWO_OVER_PI.reduce(0) { |result, number| (result << 24) + number }, 1 << (TWO_OVER_PI.length * 24))

  class << self
    def exp(value)
      unless value.finite?
        return value if value.nan? || value.positive?

        return 0.0
      end
      return Float::INFINITY if value > 7.09782712893383973096e2
      return 0.0 if value < -7.45133219101941108420e2

      high = high_word(value) & 0x7fffffff
      sign = value.negative? ? 1 : 0
      exponent = 0
      upper = 0.0
      lower = 0.0
      if high > 0x3fd62e42
        if high < 0x3ff0a2b2
          return 2.718281828459045 if value == 1

          upper = value - (sign.zero? ? 6.93147180369123816490e-1 : -6.93147180369123816490e-1)
          lower = sign.zero? ? 1.90821492927058770002e-10 : -1.90821492927058770002e-10
          exponent = 1 - sign - sign
        else
          exponent = ((1.44269504088896338700 * value) + (sign.zero? ? 0.5 : -0.5)).truncate
          upper = value - (exponent * 6.93147180369123816490e-1)
          lower = exponent * 1.90821492927058770002e-10
        end
        value = upper - lower
      elsif high < 0x3e300000
        return 1.0 + value
      end

      square = value * value
      correction = value - (square * (1.66666666666666019037e-1 + (square * (-2.77777777770155933842e-3 + (square * (6.61375632143793436117e-5 + (square * (-1.65339022054652515390e-6 + (square * 4.13813679705723846039e-8)))))))))
      return 1.0 - (((value * correction) / (correction - 2.0)) - value) if exponent.zero?

      result = 1.0 - ((lower - ((value * correction) / (2.0 - correction))) - upper)
      return result * 2.0 * 8.988465674311579539e307 if exponent == 1024
      return result * Math.ldexp(1.0, exponent) if exponent >= -1021

      result * Math.ldexp(1.0, exponent + 1000) * 9.33263618503218878990e-302
    end

    def sin(value)
      return Float::NAN unless value.finite?
      return kernel_sin(value, 0.0, false) if (high_word(value) & 0x7fffffff) <= 0x3fe921fb

      count, high, low = reduce_angle(value)
      case count & 3
      when 0 then kernel_sin(high, low, true)
      when 1 then kernel_cos(high, low)
      when 2 then -kernel_sin(high, low, true)
      when 3 then -kernel_cos(high, low)
      end
    end

    def cos(value)
      return Float::NAN unless value.finite?
      return kernel_cos(value, 0.0) if (high_word(value) & 0x7fffffff) <= 0x3fe921fb

      count, high, low = reduce_angle(value)
      case count & 3
      when 0 then kernel_cos(high, low)
      when 1 then -kernel_sin(high, low, true)
      when 2 then -kernel_cos(high, low)
      when 3 then kernel_sin(high, low, true)
      end
    end

    def tan(value)
      return Float::NAN unless value.finite?
      return kernel_tan(value, 0.0, 1) if (high_word(value) & 0x7fffffff) <= 0x3fe921fb

      count, high, low = reduce_angle(value)
      kernel_tan(high, low, 1 - ((count & 1) << 1))
    end

    private

    def high_word(value)
      [value].pack('G').unpack1('Q>') >> 32
    end

    def from_words(high, low = 0)
      [((high & 0xffffffff) << 32) | (low & 0xffffffff)].pack('Q>').unpack1('G')
    end

    def without_low_word(value)
      from_words(high_word(value))
    end

    def reduce_angle(value)
      high_word = high_word(value) & 0x7fffffff
      if high_word < 0x4002d97c
        offset = value.negative? ? -1 : 1
        part = value - (offset * PIO2[0])
        if high_word == 0x3ff921fb
          part -= offset * PIO2[2]
          high = part - (offset * PIO2[3])
          low = (part - high) - (offset * PIO2[3])
        else
          high = part - (offset * PIO2[1])
          low = (part - high) - (offset * PIO2[1])
        end
        return [offset, high, low]
      end
      return reduce_large_angle(value) if high_word > 0x413921fb

      count = ((value.abs * 6.36619772367581382433e-1) + 0.5).truncate
      part = value.abs - (count * PIO2[0])
      tail = count * PIO2[1]
      high = part - tail
      unless count < 32 && high_word != PIO2_HIGH_WORDS[count - 1]
        exponent = high_word >> 20
        if exponent - ((high_word(high) >> 20) & 0x7ff) > 16
          previous = part
          tail = count * PIO2[2]
          part = previous - tail
          tail = (count * PIO2[3]) - ((previous - part) - tail)
          high = part - tail
          if exponent - ((high_word(high) >> 20) & 0x7ff) > 49
            previous = part
            tail = count * PIO2[4]
            part = previous - tail
            tail = (count * PIO2[5]) - ((previous - part) - tail)
            high = part - tail
          end
        end
      end
      low = (part - high) - tail
      value.negative? ? [-count, -high, -low] : [count, high, low]
    end

    def reduce_large_angle(value)
      ratio = value.to_r * TWO_OVER_PI_RATIO
      count = (ratio + Rational(1, 2)).floor
      remainder = value.to_r - (count / TWO_OVER_PI_RATIO)
      high = rational_float(remainder)
      low = rational_float(remainder - high.to_r)
      [count, high, low]
    end

    def rational_float(value)
      return 0.0 if value.zero?

      numerator = value.numerator.abs
      denominator = value.denominator
      exponent = numerator.bit_length - denominator.bit_length
      exponent -= 1 if exponent.negative? ? numerator << -exponent < denominator : numerator < denominator << exponent
      shift = 52 - exponent
      scaled_numerator, scaled_denominator = shift.negative? ? [numerator, denominator << -shift] : [numerator << shift, denominator]
      mantissa, remainder = scaled_numerator.divmod(scaled_denominator)
      mantissa += 1 if remainder * 2 > scaled_denominator || (remainder * 2 == scaled_denominator && mantissa.odd?)
      result = Math.ldexp(mantissa.to_f, exponent - 52)
      value.negative? ? -result : result
    end

    def kernel_sin(value, tail, corrected)
      return value if (high_word(value) & 0x7fffffff) < 0x3e400000

      square = value * value
      cube = square * value
      remainder = 8.33333333332248946124e-3 + (square * (-1.98412698298579493134e-4 + (square * (2.75573137070700676789e-6 + (square * (-2.50507602534068634195e-8 + (square * 1.58969099521155010221e-10)))))))
      return value + (cube * (-1.66666666666666324348e-1 + (square * remainder))) unless corrected

      value - (((square * ((0.5 * tail) - (cube * remainder))) - tail) - (cube * -1.66666666666666324348e-1))
    end

    def kernel_cos(value, tail)
      high_word = high_word(value) & 0x7fffffff
      return 1.0 if high_word < 0x3e400000

      square = value * value
      remainder = square * (4.16666666666666019037e-2 + (square * (-1.38888888888741095749e-3 + (square * (2.48015872894767294178e-5 + (square * (-2.75573143513906633035e-7 + (square * (2.08757232129817482790e-9 + (square * -1.13596475577881948265e-11))))))))))
      return 1.0 - ((0.5 * square) - ((square * remainder) - (value * tail))) if high_word < 0x3fd33333

      quarter = high_word > 0x3fe90000 ? 0.28125 : from_words(high_word - 0x00200000)
      reduced = (0.5 * square) - quarter
      (1.0 - quarter) - (reduced - ((square * remainder) - (value * tail)))
    end

    def kernel_tan(value, tail, direction)
      high = high_word(value)
      absolute_high = high & 0x7fffffff
      if absolute_high < 0x3e300000
        return 1.0 / value.abs if value.zero? && direction == -1
        return value if direction == 1

        sum = value + tail
        upper = without_low_word(sum)
        error = tail - (upper - value)
        inverse = -1.0 / sum
        high_inverse = without_low_word(inverse)
        return high_inverse + (inverse * ((1.0 + (high_inverse * upper)) + (high_inverse * error)))
      end

      if absolute_high >= 0x3fe59428
        if high >= 0x80000000
          value = -value
          tail = -tail
        end
        value = (7.85398163397448278999e-1 - value) + (3.06161699786838301793e-17 - tail)
        tail = 0.0
      end
      square = value * value
      fourth = square * square
      coefficients = TAN_COEFFICIENTS
      odd = coefficients[1] + (fourth * (coefficients[3] + (fourth * (coefficients[5] + (fourth * (coefficients[7] + (fourth * (coefficients[9] + (fourth * coefficients[11])))))))))
      even = square * (coefficients[2] + (fourth * (coefficients[4] + (fourth * (coefficients[6] + (fourth * (coefficients[8] + (fourth * (coefficients[10] + (fourth * coefficients[12]))))))))))
      cube = square * value
      remainder = tail + (square * ((cube * (odd + even)) + tail))
      remainder += coefficients[0] * cube
      sum = value + remainder
      return (1 - ((high >> 30) & 2)) * (direction - (2.0 * (value - (((sum * sum) / (sum + direction)) - remainder)))) if absolute_high >= 0x3fe59428
      return sum if direction == 1

      upper = without_low_word(sum)
      error = remainder - (upper - value)
      inverse = -1.0 / sum
      high_inverse = without_low_word(inverse)
      high_inverse + (inverse * ((1.0 + (high_inverse * upper)) + (high_inverse * error)))
    end
  end
end
