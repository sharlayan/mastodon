# frozen_string_literal: true

class Sharlayan::Dice::Budget
  MAX_DRAWS = 1_024
  MAX_STEPS = 100_000
  TIMEOUT = 3

  def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @clock = clock
    @deadline = @clock.call + TIMEOUT
    @draws = 0
    @steps = 0
  end

  def tick!
    @steps += 1
    raise Sharlayan::Dice::Error, :limit if @steps > MAX_STEPS || @clock.call >= @deadline
  end

  def draw!
    tick!
    @draws += 1
    raise Sharlayan::Dice::Error, :limit if @draws > MAX_DRAWS
  end
end
