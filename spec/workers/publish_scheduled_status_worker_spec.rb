# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PublishScheduledStatusWorker do
  subject { described_class.new }

  let(:scheduled_status) { Fabricate(:scheduled_status, params: { text: 'Hello world, future!' }) }

  describe 'perform' do
    before do
      subject.perform(scheduled_status.id)
    end

    context 'when the account is not disabled' do
      let(:user) { Fabricate(:user) }
      let(:scheduled_status) { Fabricate(:scheduled_status, account: user.account, params: { text: 'Hello world, future!', quoted_status_id: Fabricate(:status, account: user.account).id }) }

      it 'creates a status and removes scheduled record' do
        expect(scheduled_status.account.statuses.first.text).to eq 'Hello world, future!'
        expect(scheduled_status.account.statuses.first.quote).to_not be_nil

        expect(ScheduledStatus.find_by(id: scheduled_status.id)).to be_nil
      end

      context 'with a drive attachment' do
        let(:drive_file) { DriveFile.create!(account: user.account, file: attachment_fixture('attachment.jpg')) }
        let(:pointer) { drive_file.build_pointer(user.account) }
        let(:scheduled_status) do
          Fabricate(:scheduled_status, account: user.account, params: { text: 'Hello world, future!' }).tap do |record|
            pointer.scheduled_status = record
            pointer.save!
            record.update!(params: record.params.merge('media_ids' => [pointer.id.to_s]))
          end
        end

        it 'keeps the drive file protected while moving its pointer to the status' do
          expect(pointer.reload.scheduled_status_id).to be_nil
          expect(pointer.status_id).to eq(scheduled_status.account.statuses.first.id)
          expect(drive_file.reload).to be_attached
        end
      end

      context 'with an implicit quote' do
        let(:quoted_status) { Fabricate(:status, account: Fabricate(:account, domain: 'example.com')) }
        let(:scheduled_status) do
          Fabricate(
            :scheduled_status,
            account: user.account,
            params: { text: 'Hello world, future!', quoted_status_id: quoted_status.id, implicit_quote_from_url: true }
          )
        end

        it 'publishes a legacy accepted quote without requesting approval' do
          status = scheduled_status.account.statuses.first

          expect(status.quote).to be_legacy
          expect(status.quote).to be_accepted
          expect(ActivityPub::QuoteRequestWorker.jobs).to be_empty
        end
      end
    end

    context 'when the account is disabled' do
      let(:scheduled_status) { Fabricate(:scheduled_status, account: Fabricate(:account, user: Fabricate(:user, disabled: true))) }

      it 'does not create a status and removes scheduled record' do
        expect(Status.count).to eq 0

        expect(ScheduledStatus.find_by(id: scheduled_status.id)).to be_nil
      end
    end
  end
end
