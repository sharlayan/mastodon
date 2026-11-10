# frozen_string_literal: true

require 'rails_helper'

RSpec.describe REST::AvatarDecorationMuteSerializer do
  it 'returns the expected attributes for account and domain mutes' do
    account_mute = Fabricate(:avatar_decoration_mute)
    domain_mute = AvatarDecorationMute.create!(account: Fabricate(:account), target_domain: 'example.com')
    account_json = serialized_record_json(account_mute, described_class)
    domain_json = serialized_record_json(domain_mute, described_class)

    expect(account_json).to include('id' => account_mute.id.to_s, 'target_account_id' => account_mute.target_account_id.to_s)
    expect(account_json['target_domain']).to be_nil
    expect(domain_json).to include('id' => domain_mute.id.to_s, 'target_domain' => 'example.com')
    expect(domain_json['target_account_id']).to be_nil
  end
end
