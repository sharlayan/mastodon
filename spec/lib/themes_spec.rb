# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Themes do
  subject(:themes) { described_class.send(:new) }

  before do
    stub_const('Themes::GLITCH_ONLY', false)
    stub_const('Themes::DISABLED_SKINS', [])
  end

  describe '#flavours' do
    it 'includes the legacy glitch flavour alongside existing flavours' do
      expect(themes.flavours).to include('glitch', 'glitch-classic', 'vanilla')
    end

    context 'when only glitch compatible flavours are enabled' do
      before { stub_const('Themes::GLITCH_ONLY', true) }

      it 'keeps the legacy glitch flavour and excludes vanilla' do
        expect(themes.flavours).to include('glitch', 'glitch-classic')
        expect(themes.flavours).to_not include('vanilla')
      end

      context 'when compatibility metadata contains a false string' do
        before do
          path = Rails.root.join('app', 'javascript', 'flavours', 'glitch-classic', 'theme.yml')
          data = YAML.load_file(path).merge('glitch_only_compatible' => 'false')
          allow(YAML).to receive(:load_file).and_call_original
          allow(YAML).to receive(:load_file).with(path).and_return(data)
        end

        it 'excludes the incompatible flavour' do
          expect(themes.flavours).to_not include('glitch-classic')
        end
      end
    end
  end

  describe 'legacy glitch assets' do
    it 'shares the glitch JavaScript entrypoints and locale catalogue' do
      legacy = themes.flavour('glitch-classic')
      glitch = themes.flavour('glitch')

      expect(legacy['pack_directory']).to eq(glitch['pack_directory'])
      expect(legacy['locales']).to match_array(glitch['locales'])
      expect(legacy['locales']).to include('en', 'ja', 'ko')
    end

    it 'provides both skins with automatic, light, and dark color schemes' do
      expect(themes.skins_for('glitch-classic')).to contain_exactly('default', 'birdsiteui')

      %w(default birdsiteui).each do |skin|
        expect(themes.supported_color_schemes('glitch-classic', skin)).to eq(%w(auto light dark))
        expect(themes.resolve_color_scheme('glitch-classic', skin, 'light')).to eq('light')
        expect(themes.resolve_color_scheme('glitch-classic', skin, 'dark')).to eq('dark')
      end
    end

    context 'when BirdSiteUI is disabled' do
      before { stub_const('Themes::DISABLED_SKINS', ['birdsiteui']) }

      it 'keeps the default skin available' do
        expect(themes.skins_for('glitch-classic')).to eq(['default'])
      end
    end
  end
end
