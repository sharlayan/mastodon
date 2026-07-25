# frozen_string_literal: true

require 'rails_helper'

RSpec.describe REST::RoleSerializer do
  subject { serialized_record_json(role, described_class) }

  let(:everyone) do
    Fabricate.build(:user_role, permissions: 0)
  end
  let(:role) do
    Fabricate.build(:user_role, id: 2342, name: 'test role', color: '#ABC', highlighted: true, permissions: 2300, collection_limit: 11)
  end

  before do
    allow(UserRole).to receive(:everyone).and_return(everyone)
  end

  it 'includes the relevant attributes' do
    expect(subject)
      .to include({
        'id' => '2342',
        'name' => 'test role',
        'color' => '#ABC',
        'highlighted' => true,
        'permissions' => '2300',
      })
  end

  context 'when collections are enabled' do
    it 'includes the relevant attributes' do
      expect(subject)
        .to include({
          'id' => '2342',
          'name' => 'test role',
          'color' => '#ABC',
          'highlighted' => true,
          'permissions' => '2300',
          'collection_limit' => 11,
        })
    end
  end

  it 'omits community permissions outside roleplay mode' do
    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') do
      expect(subject).to_not have_key('extra_permissions')
    end
  end

  it 'includes community permissions in roleplay mode' do
    role.extra_permissions = UserRole::EXTRA_FLAGS[:view_admin_timeline]

    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
      expect(subject['extra_permissions']).to eq(UserRole::EXTRA_FLAGS[:view_admin_timeline].to_s)
    end
  end
end
