# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuthorizedFetchHelper do
  around do |example|
    ClimateControl.modify(AUTHORIZED_FETCH: nil) { example.run }
  end

  before do
    allow(Rails.configuration.x.mastodon).to receive(:limited_federation_mode).and_return(false)
    allow(Mastodon::Feature).to receive(:bloom_filters_enabled?).and_return(false)
  end

  context 'when the setting is unset' do
    before { Setting.authorized_fetch = nil }

    it 'preserves the legacy unauthenticated-fetch behavior' do
      expect(helper.authorized_fetch_mode).to eq('none')
      expect(helper.authorized_fetch_mode?).to be false
      expect(helper.actors_require_signature?).to be false
    end
  end

  context 'when actor authentication is explicitly selected' do
    before { Setting.authorized_fetch = 'actors' }

    it 'requires signatures for actors without enabling full authorized fetch' do
      expect(helper.authorized_fetch_mode).to eq('actors')
      expect(helper.authorized_fetch_mode?).to be false
      expect(helper.actors_require_signature?).to be true
    end
  end
end
