# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::AdminTimeline do
  let(:owner_role) { UserRole.find_by(name: 'Owner') }
  let(:owner) { Fabricate(:user, role: owner_role).account }
  let(:account) { Fabricate(:account) }

  describe '.owner_conversation?' do
    it 'recognizes a direct post authored by an owner' do
      status = Fabricate(:status, account: owner, visibility: :direct, local_only: true)

      expect(described_class.owner_conversation?(status)).to be(true)
    end

    it 'recognizes a direct post mentioning an owner' do
      status = Fabricate(:status, account: account, visibility: :direct, local_only: true)
      Fabricate(:mention, status: status, account: owner)

      expect(described_class.owner_conversation?(status)).to be(true)
    end

    it 'does not treat an owner public post as a protected conversation' do
      status = Fabricate(:status, account: owner, visibility: :public, local_only: true)

      expect(described_class.owner_conversation?(status)).to be(false)
    end
  end
end
