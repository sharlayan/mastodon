# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatusPolicy, type: :model do
  subject { described_class }

  let(:owner_role) { UserRole.find_by(name: 'Owner') }
  let(:owner)      { Fabricate(:user, role: owner_role).account }
  let(:admin)      { Fabricate(:admin_user).account }
  let(:author)     { Fabricate(:account, username: 'author') }
  let(:stranger)   { Fabricate(:account, username: 'stranger') }
  let(:status)     { Fabricate(:status, account: author, visibility: :public) }

  around do |example|
    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') { example.run }
  end

  before do
    RpHiddenStatus.create!(status: status)
  end

  permissions :show? do
    it 'permits only the owner to view a hidden status' do
      expect(subject).to permit(owner, status)
      expect(subject).to_not permit(admin, status)
      expect(subject).to_not permit(author, status)
      expect(subject).to_not permit(stranger, status)
      expect(subject).to_not permit(nil, status)
    end
  end

  permissions :quote?, :reblog?, :favourite?, :react? do
    it 'denies owner interactions with a hidden status' do
      expect(subject).to_not permit(owner, status)
    end
  end

  context 'when roleplay mode is disabled' do
    around do |example|
      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') { example.run }
    end

    permissions :show? do
      it 'falls through to normal visibility rules for a public status' do
        expect(subject).to permit(stranger, status)
      end
    end
  end

  context 'with the destroy permission' do
    let(:visible_status) { Fabricate(:status, account: author) }

    before do
      Setting.soft_hide_deletion = true
    end

    after do
      Setting.soft_hide_deletion = false
    end

    permissions :destroy? do
      it 'permits only the owner to delete another local account status while soft-hide deletion is enabled' do
        remote_status = Fabricate(:status, account: Fabricate(:account, domain: 'remote.example'))

        expect(subject).to permit(owner, visible_status)
        expect(subject).to_not permit(admin, visible_status)
        expect(subject).to_not permit(owner, remote_status)

        Setting.soft_hide_deletion = false

        expect(subject).to_not permit(owner, visible_status)
      end
    end

    permissions :unreblog? do
      it 'does not permit the owner to undo another account reblog' do
        expect(subject).to_not permit(owner, visible_status)
      end
    end
  end
end
