# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyAccessGrant do
  subject(:grant) { described_class.new(access_token: token, permissions: permissions) }

  let(:token) { Fabricate(:accessible_access_token) }
  let(:permissions) { ['read:account', 'write:notes'] }

  it 'accepts supported permissions and checks them exactly' do
    expect(grant).to be_valid
    expect(grant.allows?('write:notes')).to be true
    expect(grant.allows?('write:blocks')).to be false
  end

  it 'rejects unsupported permissions' do
    grant.permissions = ['write:unknown']

    expect(grant).to_not be_valid
  end
end
