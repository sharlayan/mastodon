# frozen_string_literal: true

require 'rails_helper'

RSpec.describe REST::AvatarDecorationMuteSerializer do
  subject { serialized_record_json(mute, described_class) }

  context 'when targeting an account' do
    let(:mute) { Fabricate(:avatar_decoration_mute) }

    it 'returns expected attributes' do
      expect(subject).to include(
        'id' => mute.id.to_s,
        'target_account_id' => mute.target_account_id.to_s
      )
      expect(subject['target_domain']).to be_nil
    end
  end

  context 'when targeting a domain' do
    let(:mute) do
      AvatarDecorationMute.create!(account: Fabricate(:account), target_domain: 'example.com')
    end

    it 'returns expected attributes' do
      expect(subject).to include(
        'id' => mute.id.to_s,
        'target_domain' => 'example.com'
      )
      expect(subject['target_account_id']).to be_nil
    end
  end
end
