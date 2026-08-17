# frozen_string_literal: true

require 'rails_helper'

RSpec.describe REST::RoleSerializer do
  subject { serialized_record_json(role, described_class) }

  let(:everyone) do
    Fabricate.build(:user_role, permissions: 0)
  end
  let(:role) do
    Fabricate.build(:user_role, id: 2342, name: 'test role', color: '#ABC', highlighted: true, permissions: 2300, collection_limit: 11, page_limit: 321, daily_page_limit: 12)
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
          'page_limit' => 321,
          'daily_page_limit' => 12,
        })
    end
  end

  it 'omits community permissions while the management timeline gate is off' do
    [
      { OC_ROLEPLAY_OPTION: 'false', OC_ADMIN_TIMELINE_OPTION: 'false' },
      { OC_ROLEPLAY_OPTION: 'true', OC_ADMIN_TIMELINE_OPTION: 'false' },
    ].each do |env|
      ClimateControl.modify(**env) do
        expect(subject).to_not have_key('extra_permissions')
      end
    end
  end

  it 'includes community permissions once the management timeline is enabled' do
    role.extra_permissions = UserRole::EXTRA_FLAGS[:view_admin_timeline]

    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true', OC_ADMIN_TIMELINE_OPTION: 'true') do
      expected = UserRole::EXTRA_FLAGS.values_at(:view_admin_timeline, :view_followers_admin_timeline).reduce(&:|)
      expect(subject['extra_permissions']).to eq(expected.to_s)
    end
  end
end
