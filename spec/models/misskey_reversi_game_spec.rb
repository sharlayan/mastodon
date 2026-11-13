# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyReversiGame do
  let(:host) { Fabricate(:account) }
  let(:guest) { Fabricate(:account) }
  let(:game) { described_class.create!(account1: host, account2: guest, map: MisskeyCompat::ReversiEngine::DEFAULT_MAP, black: 2) }

  it 'validates maps, bw and the turn time limit' do
    expect(described_class.valid_map?(%w(---- -wb- -bw- ----))).to be(true)
    expect(described_class.valid_map?([])).to be(false)
    expect(described_class.valid_map?(%w(--- --))).to be(false)
    expect(described_class.valid_map?(%w(-x-))).to be(false)
    expect(described_class.valid_map?(['-' * 33])).to be(false)
    expect(described_class.new(account1: host, account2: guest, map: %w(---), bw: '3')).to_not be_valid
    expect(described_class.new(account1: host, account2: guest, map: %w(---), time_limit_for_each_turn: -1)).to_not be_valid
  end

  it 'maps participants to slots and colors' do
    expect(game.slot_of(host)).to eq(1)
    expect(game.slot_of(guest)).to eq(2)
    expect(game.slot_of(Fabricate(:account))).to be_nil
    expect(game.color_of(guest)).to be(true)
    expect(game.color_of(host)).to be(false)
    expect(game.account_id_for_color(true)).to eq(guest.id)
    expect(game.account_id_for_color(false)).to eq(host.id)
    expect(game.other_account_id(host.id)).to eq(guest.id)
    expect(described_class.involving(guest)).to eq([game])
    expect(game.engine.turn).to be(true)
  end
end
