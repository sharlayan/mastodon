# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyCompat::ReversiEngine do
  def restore(map, logs, llotheo: false, can_put_everywhere: false, looped_board: false)
    described_class.restore(map: map, llotheo: llotheo, can_put_everywhere: can_put_everywhere, looped_board: looped_board, logs: logs)
  end

  it 'matches misskey-reversi turns, flips and crc32 on the default board' do
    game = described_class.new(described_class::DEFAULT_MAP)

    expect(game).to have_attributes(turn: true, crc32: 1_090_129_541, black_count: 2, white_count: 2, ended?: false)
    expect(game.puttable_places(true)).to eq([19, 26, 37, 44])
    expect(game.can_put?(true, 0)).to be(false)
    expect(game.can_put?(true, 64)).to be(false)

    game.put_stone(37)
    expect(game).to have_attributes(turn: false, black_count: 4, white_count: 1)

    restored = restore(described_class::DEFAULT_MAP, [[1137, 1, 0, 37], [137, 0, 0, 43], [137, 1, 0, 50], [137, 0, 0, 45]])
    expect(restored).to have_attributes(turn: true, crc32: -164_479_268)
  end

  it 'applies looped boards, llotheo scoring, put-everywhere mode and boards decided at the start' do
    looped = restore(%w(b-w- ---- w--- ---b), [[1137, 1, 0, 5], [137, 0, 0, 10]], llotheo: true, looped_board: true)
    expect(looped).to have_attributes(ended?: true, winner: true, black_count: 2, white_count: 4, crc32: -1_586_334_466)

    flat = described_class.new(%w(b-w- ---- w--- ---b))
    expect(flat).to have_attributes(turn: nil, ended?: true, winner: nil, crc32: -2_072_048_043)

    expect(described_class.new(%w(b-- --- ---))).to have_attributes(ended?: true, winner: true, crc32: -606_922_085)

    everywhere = restore(%w(--- ---), [[1137, 1, 0, 5], [137, 0, 0, 1], [137, 1, 0, 3], [137, 0, 0, 2], [137, 1, 0, 4], [137, 0, 0, 0]], can_put_everywhere: true)
    expect(everywhere).to have_attributes(ended?: true, winner: nil, black_count: 3, white_count: 3, crc32: 173_849_889)
    expect(described_class.new(['- -'], can_put_everywhere: true).can_put?(true, 1)).to be(false)
  end

  it 'round-trips serialized logs with relative timestamps' do
    logs = [described_class::Log.new(time: 1000, player: true, operation: 'put', pos: 19), described_class::Log.new(time: 1500, player: false, operation: 'put', pos: 18)]
    serialized = described_class.serialize_logs(logs)

    expect(serialized).to eq([[1000, 1, 0, 19], [500, 0, 0, 18]])
    expect(described_class.deserialize_logs(serialized).map(&:to_h)).to eq(logs.map(&:to_h))
  end
end
