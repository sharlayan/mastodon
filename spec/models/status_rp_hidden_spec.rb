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

    it 'excludes hidden statuses from the default scope and account associations while with_rp_hidden and rp_hidden? expose them' do
      expect(described_class.all).to include(visible_status)
      expect(described_class.all).to_not include(hidden_status)
      expect(described_class.find_by(id: hidden_status.id)).to be_nil
      expect(hidden_status.account.statuses).to_not include(hidden_status)
      expect(described_class.with_rp_hidden).to include(visible_status, hidden_status)
      expect(described_class.with_rp_hidden.find(hidden_status.id).rp_hidden?).to be(true)
      expect(visible_status.rp_hidden?).to be(false)
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
