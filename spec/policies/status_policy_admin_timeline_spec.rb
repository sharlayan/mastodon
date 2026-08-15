# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatusPolicy, type: :model do
  subject { described_class }

  let(:owner_role) { UserRole.find_by(name: 'Owner') }
  let(:owner)      { Fabricate(:user, role: owner_role).account }
  let(:viewer_role) { Fabricate(:user_role, permissions: UserRole::FLAGS[:manage_reports], extra_permissions: UserRole::EXTRA_FLAGS[:view_admin_timeline]) }
  let(:viewer)     { Fabricate(:user, role: viewer_role).account }
  let(:stranger)   { Fabricate(:account, username: 'stranger') }
  let(:author)     { Fabricate(:account, username: 'author') }

  around do |example|
    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true', OC_ADMIN_TIMELINE_OPTION: 'true') { example.run }
  end

  permissions :show? do
    context 'with a local-only followers-only status' do
      let(:status) { Fabricate(:status, account: author, visibility: :private, local_only: true) }

      it 'permits the owner' do
        expect(subject).to permit(owner, status)
      end

      it 'permits a management timeline privilege holder' do
        expect(subject).to permit(viewer, status)
      end

      it 'denies an account without the privilege' do
        expect(subject).to_not permit(stranger, status)
      end
    end

    context 'with a status the management timeline never lists' do
      let(:status) { Fabricate(:status, account: author, visibility: :private, local_only: false) }

      it 'denies a management timeline privilege holder' do
        expect(subject).to_not permit(viewer, status)
      end
    end

    context 'with a direct status an owner takes part in' do
      let(:status) { Fabricate(:status, account: owner, visibility: :direct, local_only: true) }

      it 'permits the owner' do
        expect(subject).to permit(owner, status)
      end

      it 'denies a management timeline privilege holder' do
        expect(subject).to_not permit(viewer, status)
      end
    end

    context 'with a direct status mentioning an owner' do
      let(:status) { Fabricate(:status, account: author, visibility: :direct, local_only: true) }

      before { Fabricate(:mention, status: status, account: owner) }

      it 'denies a management timeline privilege holder' do
        expect(subject).to_not permit(viewer, status)
      end
    end

    context 'with a public status the privilege holder could already see' do
      let(:status) { Fabricate(:status, account: author, visibility: :public) }

      it 'permits a management timeline privilege holder' do
        expect(subject).to permit(viewer, status)
      end
    end

    context 'when the management timeline is disabled' do
      let(:status) { Fabricate(:status, account: author, visibility: :private, local_only: true) }

      around do |example|
        ClimateControl.modify(OC_ADMIN_TIMELINE_OPTION: nil) { example.run }
      end

      it 'denies a management timeline privilege holder' do
        expect(subject).to_not permit(viewer, status)
      end
    end
  end

  permissions :quote?, :reblog?, :favourite?, :react? do
    context 'with a status only the management timeline bypass exposes' do
      let(:status) { Fabricate(:status, account: author, visibility: :private, local_only: true) }

      it 'denies a management timeline privilege holder' do
        expect(subject).to_not permit(viewer, status)
      end

      it 'denies the owner' do
        expect(subject).to_not permit(owner, status)
      end
    end
  end

  permissions :reblog?, :favourite?, :react? do
    context 'with a public status the privilege holder could already see' do
      let(:status) { Fabricate(:status, account: author, visibility: :public) }

      it 'permits a management timeline privilege holder' do
        expect(subject).to permit(viewer, status)
      end
    end
  end
end
