# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyCompat::MiId do
  describe '.encode / .decode round-trip' do
    [
      116_898_149_598_388_143,
      116_880_084_531_513_930,
      1,
      5,
      42,
      999_999,
      2**62,
    ].each do |id|
      it "round-trips #{id}" do
        encoded = described_class.encode(id)
        expect(encoded).to match(/\A[0-9a-z]{16}\z/)
        expect(described_class.decode(encoded)).to eq(id.to_s)
      end
    end
  end

  describe '.encode' do
    it 'returns nil for nil' do
      expect(described_class.encode(nil)).to be_nil
    end

    it 'produces 16-character lowercase base36 strings' do
      expect(described_class.encode(116_898_149_598_388_143)).to match(/\A[0-9a-z]{16}\z/)
    end

    it 'encodes snowflake ids with a non-zero leading character' do
      expect(described_class.encode(116_898_149_598_388_143)).to_not start_with('0')
    end

    it 'encodes small sequential ids with a leading zero (scheme disambiguation)' do
      expect(described_class.encode(5)).to start_with('0')
    end

    it 'preserves ordering for snowflake ids' do
      a = 116_880_102_873_070_420
      b = 116_880_105_543_103_933
      expect(described_class.encode(a) < described_class.encode(b)).to eq(a < b)
    end

    it 'preserves ordering for small ids' do
      expect(described_class.encode(5) < described_class.encode(42)).to be(true)
    end
  end

  describe '.decode' do
    it 'returns nil for nil' do
      expect(described_class.decode(nil)).to be_nil
    end

    it 'passes through values that are not our encoding (raw snowflake)' do
      expect(described_class.decode('116898149598388143')).to eq('116898149598388143')
    end

    it 'passes through non-matching strings unchanged' do
      expect(described_class.decode('not-an-id')).to eq('not-an-id')
    end
  end

  describe 'Aria pagination semantics' do
    it 'maps a date+1ms increment (Aria Id.next) to +65536 in snowflake space' do
      id = 116_880_102_873_070_420
      encoded = described_class.encode(id)
      next_time = (encoded[0, 8].to_i(36) + 1).to_s(36).rjust(8, '0')
      next_id = described_class.decode("#{next_time}#{encoded[8, 8]}")
      expect(next_id.to_i - id).to eq(65_536)
    end
  end
end
