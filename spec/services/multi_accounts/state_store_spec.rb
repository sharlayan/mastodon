# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MultiAccounts::StateStore do
  let(:state) { SecureRandom.hex(32) }
  let(:nonce) { SecureRandom.uuid }

  before { described_class.store!(state, nonce, 1) }

  it 'consumes a state only once and refuses a different nonce' do
    other_state = SecureRandom.hex(32)
    described_class.store!(other_state, nonce, 1)

    expect(described_class.consume!(state, nonce)).to be true
    expect(described_class.consume!(state, nonce)).to be false
    expect(described_class.consume!(other_state, SecureRandom.uuid)).to be false
  end
end
