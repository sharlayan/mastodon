# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::Status::AdminTimelineGuard do
  let(:account) { Fabricate(:account) }
  let(:remote_account) { Fabricate(:account, domain: 'remote.example', username: 'stranger') }

  def status_for(visibility, local_only:)
    Fabricate(:status, account: account, visibility: visibility, local_only: local_only)
  end

  describe '#admin_timeline_eligible?' do
    it 'accepts public posts regardless of federation' do
      expect(status_for(:public, local_only: false)).to be_admin_timeline_eligible
      expect(status_for(:public, local_only: true)).to be_admin_timeline_eligible
    end

    it 'accepts restricted posts only when they are local-only' do
      %i(unlisted private direct).each do |visibility|
        expect(status_for(visibility, local_only: true)).to be_admin_timeline_eligible
        expect(status_for(visibility, local_only: false)).to_not be_admin_timeline_eligible
      end
    end

    it 'rejects local-only conversations that mention a remote account' do
      status = status_for(:direct, local_only: true)
      Fabricate(:mention, status: status, account: remote_account)

      expect(status.reload).to_not be_admin_timeline_eligible
    end

    it 'rejects local-only conversations replying to a remote account' do
      status = Fabricate(:status, account: account, visibility: :private, local_only: true, in_reply_to_account_id: remote_account.id)

      expect(status).to_not be_admin_timeline_eligible
    end

    it 'keeps public posts that mention a remote account' do
      status = status_for(:public, local_only: false)
      Fabricate(:mention, status: status, account: remote_account)

      expect(status.reload).to be_admin_timeline_eligible
    end
  end

  describe '.admin_timeline_eligible' do
    it 'excludes federated restricted posts and conversations with remote participants' do
      federated_public = status_for(:public, local_only: false)
      federated_restricted = %i(direct private unlisted).map { |visibility| status_for(visibility, local_only: false) }
      local_restricted = %i(direct private unlisted).map { |visibility| status_for(visibility, local_only: true) }
      mentioning = status_for(:direct, local_only: true)
      Fabricate(:mention, status: mentioning, account: remote_account)
      replying = Fabricate(:status, account: account, visibility: :private, local_only: true, in_reply_to_account_id: remote_account.id)

      expect(Status.admin_timeline_eligible)
        .to include(federated_public, *local_restricted)
        .and not_include(*federated_restricted, mentioning, replying)
    end

    it 'treats a null local_only column as federated' do
      status = status_for(:direct, local_only: true)
      status.update_column(:local_only, nil)

      expect(Status.admin_timeline_eligible).to_not include(status)
      expect(status.reload).to_not be_admin_timeline_eligible
    end
  end
end
