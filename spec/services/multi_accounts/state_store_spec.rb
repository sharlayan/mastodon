# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MultiAccounts::StateStore do
  let(:state) { SecureRandom.hex(32) }
  let(:nonce) { SecureRandom.uuid }

  before { described_class.store!(state, nonce, 1) }

  it 'consumes a state only once' do
    expect(described_class.consume!(state, nonce)).to be true
    expect(described_class.consume!(state, nonce)).to be false
  end

  it 'refuses a different nonce' do
    expect(described_class.consume!(state, SecureRandom.uuid)).to be false
  end
end
