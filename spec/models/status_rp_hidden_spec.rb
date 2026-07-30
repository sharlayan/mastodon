# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Status do
  describe 'rp hidden scoping' do
    let!(:visible_status) { Fabricate(:status) }
    let!(:hidden_status)  { Fabricate(:status) }

    around do |example|
      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') { example.run }
    end

    before do
      RpHiddenStatus.create!(status: hidden_status)
    end

    it 'excludes hidden statuses from the default scope' do
      expect(described_class.all).to include(visible_status)
      expect(described_class.all).to_not include(hidden_status)
    end

    it 'makes hidden statuses unfindable through the default scope' do
      expect(described_class.find_by(id: hidden_status.id)).to be_nil
    end

    it 'includes hidden statuses through with_rp_hidden' do
      expect(described_class.with_rp_hidden).to include(visible_status, hidden_status)
    end

    describe '#rp_hidden?' do
      it 'is true for a hidden status' do
        expect(described_class.with_rp_hidden.find(hidden_status.id).rp_hidden?).to be(true)
      end

      it 'is false for a visible status' do
        expect(visible_status.rp_hidden?).to be(false)
      end
    end

    it 'hides the status from account statuses associations' do
      account = hidden_status.account
      expect(account.statuses).to_not include(hidden_status)
    end

    context 'when roleplay mode is disabled' do
      around do |example|
        ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') { example.run }
      end

      it 'keeps the status in normal scopes' do
        expect(described_class.all).to include(visible_status, hidden_status)
        expect(described_class.find_by(id: hidden_status.id)).to eq(hidden_status)
        expect(hidden_status.account.statuses).to include(hidden_status)
      end
    end
  end
end
