# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::Status::AdminTimelineGuard do
  let(:account) { Fabricate(:account) }

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
  end

  describe '.admin_timeline_eligible' do
    let!(:federated_public) { status_for(:public, local_only: false) }
    let!(:federated_direct) { status_for(:direct, local_only: false) }
    let!(:federated_private) { status_for(:private, local_only: false) }
    let!(:federated_unlisted) { status_for(:unlisted, local_only: false) }
    let!(:local_direct) { status_for(:direct, local_only: true) }
    let!(:local_private) { status_for(:private, local_only: true) }
    let!(:local_unlisted) { status_for(:unlisted, local_only: true) }

    it 'excludes federated posts that are not public' do
      expect(Status.admin_timeline_eligible)
        .to include(federated_public, local_direct, local_private, local_unlisted)
        .and not_include(federated_direct)
        .and not_include(federated_private)
        .and not_include(federated_unlisted)
    end

    it 'treats a null local_only column as federated' do
      status = status_for(:direct, local_only: true)
      status.update_column(:local_only, nil)

      expect(Status.admin_timeline_eligible).to_not include(status)
      expect(status.reload).to_not be_admin_timeline_eligible
    end
  end
end
