# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MfmDetector do
  describe '.contains_mfm?' do
    it 'returns true only for complete MFM function syntax' do
      expect(described_class.contains_mfm?('$[tada hello]')).to be true
      expect(described_class.contains_mfm?('$[spin.speed=2s text]')).to be true
      expect(described_class.contains_mfm?('$[fg.color=f00 red text]')).to be true
      expect(described_class.contains_mfm?('hello world')).to be false
      expect(described_class.contains_mfm?('just a $dollar sign')).to be false
      expect(described_class.contains_mfm?(nil)).to be false
      expect(described_class.contains_mfm?('')).to be false
      expect(described_class.contains_mfm?('$[notclosed')).to be false
    end
  end

  describe '.extract_tags' do
    it 'extracts unique known MFM tags and ignores unknown tags or blank text' do
      expect(described_class.extract_tags('$[tada hello] and $[spin.speed=1s world]')).to contain_exactly('tada', 'spin')
      expect(described_class.extract_tags('$[unknown hello] and $[tada world]')).to eq(['tada'])
      expect(described_class.extract_tags('$[tada a] $[tada b]')).to eq(['tada'])
      expect(described_class.extract_tags(nil)).to eq([])
      expect(described_class.extract_tags('')).to eq([])
    end
  end
end
