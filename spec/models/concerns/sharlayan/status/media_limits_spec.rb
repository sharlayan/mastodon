# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::Status::MediaLimits do
  it 'reads the local attachment limit from MAX_MEDIA_ATTACHMENTS within 1 to 16, defaulting to 10' do
    expect(described_class.default_local_media_attachments_limit({})).to eq(10)
    expect(described_class.default_local_media_attachments_limit('MAX_MEDIA_ATTACHMENTS' => '6')).to eq(6)
    expect(described_class.default_local_media_attachments_limit('MAX_MEDIA_ATTACHMENTS' => '40')).to eq(16)
    expect(described_class.default_local_media_attachments_limit('MAX_MEDIA_ATTACHMENTS' => '0')).to eq(1)
    expect(described_class.default_local_media_attachments_limit('MAX_MEDIA_ATTACHMENTS' => 'many')).to eq(10)
    expect(described_class.default_local_media_attachments_limit('MAX_MEDIA_ATTACHMENTS' => '')).to eq(10)
  end

  it 'applies the administrator local attachment limit to new posts within the hard cap' do
    account = Fabricate(:account)
    media = Array.new(3) { Fabricate(:media_attachment, account: account) }

    Setting.local_media_attachments_limit = 2
    expect(Status.local_media_attachments_limit).to eq(2)
    expect { PostStatusService.new.call(account, text: 'Too many', media_ids: media.map { |m| m.id.to_s }) }
      .to raise_error(Mastodon::ValidationError, I18n.t('media_attachments.validations.too_many_limited', count: 2))

    Setting.local_media_attachments_limit = 40
    expect(Status.local_media_attachments_limit).to eq(Status::MEDIA_ATTACHMENTS_LIMIT)
  end

  it 'keeps attachments of existing local posts after the local limit is lowered' do
    status = Fabricate(:status)
    attachments = Array.new(3) { Fabricate(:media_attachment, account: status.account, status: status) }
    status.update!(ordered_media_attachment_ids: attachments.map(&:id))
    Setting.local_media_attachments_limit = 2

    expect(status.reload.ordered_media_attachments.size).to eq(3)

    UpdateStatusService.new.call(status, status.account_id, text: 'Edited', media_ids: attachments.map { |m| m.id.to_s })
    expect(status.reload.ordered_media_attachment_ids).to eq(attachments.map(&:id))

    extra = Fabricate(:media_attachment, account: status.account)
    expect { UpdateStatusService.new.call(status, status.account_id, text: 'Edited again', media_ids: (attachments + [extra]).map { |m| m.id.to_s }) }
      .to raise_error(Mastodon::ValidationError)
  end

  it 'publishes a scheduled post with the attachments accepted when it was scheduled' do
    account = Fabricate(:user).account
    scheduled_status = Fabricate(:scheduled_status, account: account, params: { text: 'Later' })
    media = Array.new(3) { Fabricate(:media_attachment, account: account, scheduled_status: scheduled_status) }
    scheduled_status.update!(params: scheduled_status.params.merge('media_ids' => media.map { |m| m.id.to_s }))
    Setting.local_media_attachments_limit = 2

    PublishScheduledStatusWorker.new.perform(scheduled_status.id)

    expect(account.statuses.first.ordered_media_attachments.size).to eq(3)
  end

  it 'keeps remote edit history attachments up to the remote limit rather than the local one' do
    Setting.remote_media_attachments_limit = 16
    stub_const('Status::MEDIA_ATTACHMENTS_LIMIT', 2)
    status = Fabricate(:status, account: Fabricate(:account, domain: 'remote.example'))
    attachments = Array.new(5) { Fabricate(:media_attachment, account: status.account, status: status) }
    edit = Fabricate(:status_edit, status: status, ordered_media_attachment_ids: attachments.map(&:id), media_descriptions: Array.new(5, ''))

    expect(edit.ordered_media_attachments.map(&:id)).to eq(attachments.map(&:id))

    Setting.remote_media_attachments_limit = 4

    expect(StatusEdit.find(edit.id).ordered_media_attachments.size).to eq(4)
  end
end
