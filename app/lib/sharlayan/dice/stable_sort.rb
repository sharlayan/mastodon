# frozen_string_literal: true

class Sharlayan::Dice::StableSort
  def initialize(values, &comparison)
    @values = values.dup
    @comparison = comparison
    @runs = []
    @minimum_gallop = 7
  end

  def call
    return @values if @values.length < 2

    minimum = minimum_run(@values.length)
    base = 0
    while base < @values.length
      length = run_length(base)
      if length < minimum
        forced_length = [minimum, @values.length - base].min
        binary_insertion(base, base + length, base + forced_length)
        length = forced_length
      end
      @runs << [base, length]
      collapse
      base += length
    end
    while @runs.length > 1
      index = @runs.length - 2
      index -= 1 if index.positive? && @runs[index - 1][1] < @runs[index + 1][1]
      merge(index)
    end
    @values
  end

  private

  def minimum_run(length)
    remainder = 0
    while length >= 64
      remainder |= length & 1
      length >>= 1
    end
    length + remainder
  end

  def run_length(base)
    return 1 if base + 1 == @values.length

    descending = @comparison.call(@values[base + 1], @values[base]).negative?
    length = 2
    while base + length < @values.length
      order = @comparison.call(@values[base + length], @values[base + length - 1])
      break if descending ? order >= 0 : order.negative?

      length += 1
    end
    @values[base, length] = @values[base, length].reverse if descending
    length
  end

  def binary_insertion(base, first, last)
    (first...last).each do |position|
      pivot = @values[position]
      left = base
      right = position
      while left < right
        middle = (left + right) / 2
        if @comparison.call(pivot, @values[middle]).negative?
          right = middle
        else
          left = middle + 1
        end
      end
      @values[left + 1, position - left] = @values[left, position - left]
      @values[left] = pivot
    end
  end

  def invariant?(index)
    index < 2 || @runs[index - 2][1] > @runs[index - 1][1] + @runs[index][1]
  end

  def collapse
    while @runs.length > 1
      index = @runs.length - 2
      if !invariant?(index + 1) || !invariant?(index)
        index -= 1 if @runs[index - 1][1] < @runs[index + 1][1]
      elsif @runs[index][1] > @runs[index + 1][1]
        break
      end
      merge(index)
    end
  end

  def merge(index)
    base_a, length_a = @runs[index]
    base_b, length_b = @runs.delete_at(index + 1)
    @runs[index] = [base_a, length_a + length_b]
    skip = gallop(@values[base_b], @values, base_a, length_a, 0, right: true)
    base_a += skip
    length_a -= skip
    return if length_a.zero?

    length_b = gallop(@values[base_a + length_a - 1], @values, base_b, length_b, length_b - 1, right: false)
    return if length_b.zero?

    if length_a <= length_b
      merge_low(base_a, length_a, base_b, length_b)
    else
      merge_high(base_a, length_a, base_b, length_b)
    end
  end

  def gallop(key, array, base, length, hint, right:)
    last_offset = 0
    offset = 1
    if before?(key, array[base + hint], right)
      maximum = hint + 1
      while offset < maximum && before?(key, array[base + hint - offset], right)
        last_offset = offset
        offset = (offset * 2) + 1
      end
      offset = [offset, maximum].min
      left = hint - offset + 1
      right_boundary = hint - last_offset
    else
      maximum = length - hint
      while offset < maximum && !before?(key, array[base + hint + offset], right)
        last_offset = offset
        offset = (offset * 2) + 1
      end
      offset = [offset, maximum].min
      left = hint + last_offset + 1
      right_boundary = hint + offset
    end
    while left < right_boundary
      middle = (left + right_boundary) / 2
      if before?(key, array[base + middle], right)
        right_boundary = middle
      else
        left = middle + 1
      end
    end
    right_boundary
  end

  def before?(key, element, right)
    right ? @comparison.call(key, element).negative? : @comparison.call(element, key) >= 0
  end

  def merge_low(base_a, length_a, base_b, length_b)
    temporary = @values[base_a, length_a]
    destination = base_a
    cursor_a = 0
    cursor_b = base_b
    @values[destination] = @values[cursor_b]
    destination += 1
    cursor_b += 1
    length_b -= 1
    minimum_gallop = @minimum_gallop

    loop do
      return finish_low(temporary, cursor_a, length_a, destination, cursor_b, length_b) if length_a <= 1 || length_b.zero?

      wins_a = 0
      wins_b = 0
      loop do
        if @comparison.call(@values[cursor_b], temporary[cursor_a]).negative?
          @values[destination] = @values[cursor_b]
          cursor_b += 1
          length_b -= 1
          wins_b += 1
          wins_a = 0
        else
          @values[destination] = temporary[cursor_a]
          cursor_a += 1
          length_a -= 1
          wins_a += 1
          wins_b = 0
        end
        destination += 1
        return finish_low(temporary, cursor_a, length_a, destination, cursor_b, length_b) if length_a <= 1 || length_b.zero?
        break if wins_a >= minimum_gallop || wins_b >= minimum_gallop
      end

      minimum_gallop += 1
      loop do
        minimum_gallop = [minimum_gallop - 1, 1].max
        @minimum_gallop = minimum_gallop
        wins_a = gallop(@values[cursor_b], temporary, cursor_a, length_a, 0, right: true)
        @values[destination, wins_a] = temporary[cursor_a, wins_a]
        destination += wins_a
        cursor_a += wins_a
        length_a -= wins_a
        return finish_low(temporary, cursor_a, length_a, destination, cursor_b, length_b) if length_a <= 1

        @values[destination] = @values[cursor_b]
        destination += 1
        cursor_b += 1
        length_b -= 1
        return finish_low(temporary, cursor_a, length_a, destination, cursor_b, length_b) if length_b.zero?

        wins_b = gallop(temporary[cursor_a], @values, cursor_b, length_b, 0, right: false)
        @values[destination, wins_b] = @values[cursor_b, wins_b]
        destination += wins_b
        cursor_b += wins_b
        length_b -= wins_b
        return finish_low(temporary, cursor_a, length_a, destination, cursor_b, length_b) if length_b.zero?

        @values[destination] = temporary[cursor_a]
        destination += 1
        cursor_a += 1
        length_a -= 1
        return finish_low(temporary, cursor_a, length_a, destination, cursor_b, length_b) if length_a == 1
        break if wins_a < 7 && wins_b < 7
      end
      minimum_gallop += 1
      @minimum_gallop = minimum_gallop
    end
  end

  def finish_low(temporary, cursor_a, length_a, destination, cursor_b, length_b)
    if length_a == 1 && length_b.positive?
      @values[destination, length_b] = @values[cursor_b, length_b]
      @values[destination + length_b] = temporary[cursor_a]
    elsif length_a.positive?
      @values[destination, length_a] = temporary[cursor_a, length_a]
    end
  end

  def merge_high(base_a, length_a, base_b, length_b)
    temporary = @values[base_b, length_b]
    destination = base_b + length_b - 1
    cursor_a = base_a + length_a - 1
    cursor_b = length_b - 1
    @values[destination] = @values[cursor_a]
    destination -= 1
    cursor_a -= 1
    length_a -= 1
    minimum_gallop = @minimum_gallop

    loop do
      return finish_high(temporary, cursor_b, length_b, destination, cursor_a, length_a) if length_a.zero? || length_b <= 1

      wins_a = 0
      wins_b = 0
      loop do
        if @comparison.call(temporary[cursor_b], @values[cursor_a]).negative?
          @values[destination] = @values[cursor_a]
          cursor_a -= 1
          length_a -= 1
          wins_a += 1
          wins_b = 0
        else
          @values[destination] = temporary[cursor_b]
          cursor_b -= 1
          length_b -= 1
          wins_b += 1
          wins_a = 0
        end
        destination -= 1
        return finish_high(temporary, cursor_b, length_b, destination, cursor_a, length_a) if length_a.zero? || length_b <= 1
        break if wins_a >= minimum_gallop || wins_b >= minimum_gallop
      end

      minimum_gallop += 1
      loop do
        minimum_gallop = [minimum_gallop - 1, 1].max
        @minimum_gallop = minimum_gallop
        wins_a = length_a - gallop(temporary[cursor_b], @values, base_a, length_a, length_a - 1, right: true)
        @values[destination - wins_a + 1, wins_a] = @values[cursor_a - wins_a + 1, wins_a]
        destination -= wins_a
        cursor_a -= wins_a
        length_a -= wins_a
        return finish_high(temporary, cursor_b, length_b, destination, cursor_a, length_a) if length_a.zero?

        @values[destination] = temporary[cursor_b]
        destination -= 1
        cursor_b -= 1
        length_b -= 1
        return finish_high(temporary, cursor_b, length_b, destination, cursor_a, length_a) if length_b == 1

        wins_b = length_b - gallop(@values[cursor_a], temporary, 0, length_b, length_b - 1, right: false)
        @values[destination - wins_b + 1, wins_b] = temporary[cursor_b - wins_b + 1, wins_b]
        destination -= wins_b
        cursor_b -= wins_b
        length_b -= wins_b
        return finish_high(temporary, cursor_b, length_b, destination, cursor_a, length_a) if length_b <= 1

        @values[destination] = @values[cursor_a]
        destination -= 1
        cursor_a -= 1
        length_a -= 1
        return finish_high(temporary, cursor_b, length_b, destination, cursor_a, length_a) if length_a.zero?
        break if wins_a < 7 && wins_b < 7
      end
      minimum_gallop += 1
      @minimum_gallop = minimum_gallop
    end
  end

  def finish_high(temporary, cursor_b, length_b, destination, cursor_a, length_a)
    if length_b == 1 && length_a.positive?
      @values[destination - length_a + 1, length_a] = @values[cursor_a - length_a + 1, length_a]
      @values[destination - length_a] = temporary[cursor_b]
    elsif length_b.positive?
      @values[destination - length_b + 1, length_b] = temporary[0, length_b]
    end
  end
end
