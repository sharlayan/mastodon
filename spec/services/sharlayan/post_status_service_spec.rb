# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PostStatusService do
  subject { described_class.new }

  def sensitive_drive_pointer(account)
    drive_file = DriveFile.find(DriveFile.insert_all!([{
      account_id: account.id,
      file_content_type: 'image/jpeg',
      file_file_name: 'attachment.jpg',
      file_file_size: 1,
      storage_file_size: 1,
      sensitive: true,
      type: DriveFile.types[:image],
      created_at: Time.current,
      updated_at: Time.current,
    }]).rows.first.first)
    drive_file.build_pointer(account).tap(&:save!)
  end

  context 'when scheduling a status' do
    let!(:account) { Fabricate(:account) }
    let!(:future)  { Time.now.utc + 2.hours }

    it 'stores sensitive params for a sensitive drive file' do
      media = sensitive_drive_pointer(account)

      status = subject.call(account, text: 'drive', media_ids: [media.id], sensitive: false, scheduled_at: future)

      expect(status.params['sensitive']).to be true
    end

    it 'preserves an implicit quote for publication' do
      user = Fabricate(:user)
      quoted_status = Fabricate(:status)
      resolve_url_service = instance_double(ResolveURLService, call: quoted_status)
      Setting.auto_quote_from_url = true
      allow(user).to receive(:setting_auto_quote_from_url).and_return(true)
      allow(ResolveURLService).to receive(:new).and_return(resolve_url_service)

      status = subject.call(user.account, text: 'https://example.com/@alice/1', scheduled_at: future)

      expect(status.params).to include(
        'quoted_status_id' => quoted_status.id,
        'implicit_quote_from_url' => true
      )
    end
  end

  it 'creates a sensitive status for a sensitive drive file' do
    account = Fabricate(:account)
    media = sensitive_drive_pointer(account)

    status = subject.call(account, text: 'drive', media_ids: [media.id], sensitive: false)

    expect(status).to be_sensitive
  end

  it 'stores MFM attributes only while MFM is enabled' do
    account = Fabricate(:account)
    Setting.mfm_enabled = true

    status = subject.call(account, text: '$[x2 test]', content_type: 'text/x-mfm')

    expect(status).to have_attributes(content_type: 'text/x-mfm', mfm: true, mfm_text: '$[x2 test]')

    Setting.mfm_enabled = false

    status = subject.call(account, text: '$[x2 disabled]', content_type: 'text/x-mfm')

    expect(status).to have_attributes(content_type: 'text/plain', mfm: false, mfm_text: nil)
  end

  context 'when posting to a circle' do
    let(:account) { Fabricate(:account) }
    let(:circle) { Circle.create!(account: account, title: 'Friends') }

    it 'raises not found when circles are disabled' do
      expect do
        subject.call(account, text: 'circle post', visibility: :circle, circle_id: circle.id)
      end.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'creates the status when circles are enabled' do
      Setting.circles_enabled = true

      status = subject.call(account, text: 'circle post', visibility: :circle, circle_id: circle.id)

      expect(status)
        .to be_persisted
        .and have_attributes(visibility: 'limited', limited_scope: 'personal')
    end

    it 'persists circle and clip membership atomically with the status' do
      clip = Clip.create!(account: account, title: 'Posts')
      Setting.circles_enabled = true
      Setting.clips_enabled = true

      status = subject.call(account, text: 'saved together', visibility: :circle, circle_id: circle.id, clip_ids: [clip.id])

      expect(circle.statuses).to include(status)
      expect(clip.statuses).to include(status)
    end

    it 'rolls back the status and circle membership when clip membership fails' do
      clip = Clip.create!(account: account, title: 'Posts')
      clips = account.clips
      selected_clips = instance_double(ActiveRecord::Relation)
      clip_statuses = clip.statuses
      Setting.circles_enabled = true
      Setting.clips_enabled = true
      allow(account).to receive(:clips).and_return(clips)
      allow(clips).to receive(:where).with(id: [clip.id]).and_return(selected_clips)
      allow(selected_clips).to receive(:find_each).and_yield(clip)
      allow(clip).to receive(:statuses).and_return(clip_statuses)
      allow(clip_statuses).to receive(:<<).and_raise(ActiveRecord::RecordInvalid)

      expect do
        subject.call(account, text: 'rolled back', visibility: :circle, circle_id: circle.id, clip_ids: [clip.id])
      end.to raise_error(ActiveRecord::RecordInvalid)

      expect(account.statuses.where(text: 'rolled back')).to_not exist
      expect(circle.statuses.where(text: 'rolled back')).to_not exist
    end

    it 'creates the status but skips a selected clip that is already full' do
      stub_const('Clip::STATUSES_LIMIT', 1)
      clip = Clip.create!(account: account, title: 'Full')
      clip.clip_statuses.create!(status: Fabricate(:status))
      Setting.clips_enabled = true

      status = subject.call(account, text: 'still posted', clip_ids: [clip.id])

      expect(status).to be_persisted
      expect(clip.statuses).to_not include(status)
    end

    it 'does not federate a personal circle status' do
      Setting.circles_enabled = true

      expect do
        subject.call(account, text: 'personal', visibility: :circle, circle_id: circle.id)
      end.to_not enqueue_sidekiq_job(ActivityPub::DistributionWorker)
    end
  end

  it 'enqueues distribution after the status transaction commits' do
    baseline_transactions = ApplicationRecord.connection.open_transactions
    transaction_states = []
    allow(DistributionWorker).to receive(:perform_async) { transaction_states << ApplicationRecord.connection.open_transactions }
    allow(ActivityPub::DistributionWorker).to receive(:perform_async) { transaction_states << ApplicationRecord.connection.open_transactions }

    subject.call(Fabricate(:account), text: 'committed')

    expect(transaction_states).to eq [baseline_transactions, baseline_transactions]
  end

  context 'with automatic URL quotes enabled' do
    let(:user) { Fabricate(:user) }
    let(:quoted_status) { Fabricate(:status) }
    let(:rate_limiter) { instance_double(RateLimiter) }
    let(:resolve_url_service) { instance_double(ResolveURLService) }
    let(:events) { [] }

    before do
      Setting.auto_quote_from_url = true
      allow(user).to receive(:setting_auto_quote_from_url).and_return(true)
      allow(RateLimiter).to receive(:new).with(user.account, family: :implicit_quotes).and_return(rate_limiter)
      allow(rate_limiter).to receive(:record!) { events << :rate_limit }
      allow(ResolveURLService).to receive(:new).and_return(resolve_url_service)
      allow(resolve_url_service).to receive(:call) do
        events << :resolve
        quoted_status
      end
    end

    it 'rate limits before resolving and creates a legacy quote' do
      status = subject.call(user.account, text: 'https://example.com/@alice/1')

      expect(events).to eq %i(rate_limit resolve)
      expect(status.quote).to be_legacy
      expect(status.quote).to be_accepted
    end

    it 'does not resolve a URL when the detection rate limit is exceeded' do
      allow(rate_limiter).to receive(:record!).and_raise(Mastodon::RateLimitExceededError)

      expect do
        subject.call(user.account, text: 'https://example.com/@alice/1')
      end.to raise_error(Mastodon::RateLimitExceededError)

      expect(events).to be_empty
    end

    it 'does not inspect URLs when an explicit quote is supplied' do
      status = subject.call(user.account, text: 'https://example.com/@alice/1', quoted_status: quoted_status)

      expect(events).to be_empty
      expect(status.quote).to_not be_legacy
    end
  end
end
