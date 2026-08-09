# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mastodon::Middleware::RoleplayFederationBlock do
  let(:app) { ->(_env) { [200, {}, ['ok']] } }

  it 'blocks federation paths in roleplay mode' do
    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
      status, = described_class.new(app).call(Rack::MockRequest.env_for('/inbox'))

      expect(status).to eq(403)
    end
  end

  it 'preserves requests outside roleplay mode' do
    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') do
      status, = described_class.new(app).call(Rack::MockRequest.env_for('/inbox'))

      expect(status).to eq(200)
    end
  end
end
