# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::Dice do
  let(:cases) { JSON.parse(File.read(file_fixture('chat_dice_cases.json'))) }

  it 'matches the original calculator for recorded rolls, formulas, modifiers and errors' do
    cases.each do |test_case|
      aggregate_failures(test_case.fetch('notation')) do
        draws = test_case.fetch('draws').dup
        random = class_double(SecureRandom)
        allow(random).to receive(:random_number) do |range|
          value = draws.shift
          expect(value).to be_a(Integer)
          expect(value).to be_between(0, range - 1)
          value
        end

        if test_case['error']
          expect { described_class.new(test_case.fetch('notation'), random: random).roll }
            .to raise_error(described_class::Error) { |error| expect(error.reason.to_s).to eq(test_case.fetch('error')) }
        else
          result = described_class.new(test_case.fetch('notation'), random: random).roll
          expect(result).to eq(test_case.slice('notation', 'total', 'output').merge('version' => 1, 'engine' => '@dice-roller/rpg-dice-roller', 'engineVersion' => '5.5.1'))
          expect(draws).to be_empty
        end
      end
    end
  end

  it 'uses independent randomness for concurrent rolls and reports unavailable entropy' do
    first = class_double(SecureRandom, random_number: 0)
    last = class_double(SecureRandom, random_number: 5)
    results = [first, last].map { |random| Thread.new { described_class.new('4d6', random: random).roll.fetch('total') } }.map(&:value)
    expect(results).to eq([4, 24])

    unavailable = class_double(SecureRandom)
    allow(unavailable).to receive(:random_number).and_raise(IOError)
    expect { described_class.new('d6', random: unavailable).roll }
      .to raise_error(described_class::Error) { |error| expect(error.reason).to eq(:busy) }
  end

  it 'bounds random draws, non-random rerolls, elapsed time and evaluation steps' do
    random = class_double(SecureRandom, random_number: 0)
    expect { described_class.new('999d6+26d6', random: random).roll }
      .to raise_error(described_class::Error) { |error| expect(error.reason).to eq(:limit) }
    expect { described_class.new('999d(3/2)r=1', random: random).roll }
      .to raise_error(described_class::Error) { |error| expect(error.reason).to eq(:limit) }

    now = 0
    budget = described_class::Budget.new(clock: -> { now })
    now = described_class::Budget::TIMEOUT
    expect { described_class.new('1d6', budget: budget).roll }
      .to raise_error(described_class::Error) { |error| expect(error.reason).to eq(:limit) }

    budget = described_class::Budget.new(clock: -> { 0 })
    described_class::Budget::MAX_STEPS.times { budget.tick! }
    expect { budget.tick! }.to raise_error(described_class::Error) { |error| expect(error.reason).to eq(:limit) }
  end
end
