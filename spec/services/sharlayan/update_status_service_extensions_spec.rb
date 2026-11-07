# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::UpdateStatusServiceExtensions do
  subject(:service) { UpdateStatusService.new }

  describe '#prepare_sharlayan_media_attachments' do
    it 'retains the validated attachments and locks newly added Drive files' do
      next_media_attachments = [instance_double(MediaAttachment)]
      added_media_attachments = [instance_double(MediaAttachment)]

      allow(DriveFile).to receive(:lock_for_media_attachments)

      service.send(:prepare_sharlayan_media_attachments, next_media_attachments, added_media_attachments)

      expect(service.instance_variable_get(:@next_media_attachments)).to eq(next_media_attachments)
      expect(DriveFile).to have_received(:lock_for_media_attachments).with(added_media_attachments)
    end
  end

  describe 'MFM on edit' do
    let(:account) { Fabricate(:account) }

    around do |example|
      mfm_enabled = Setting.mfm_enabled
      mfm_allow_composition = Setting.mfm_allow_composition
      example.run
    ensure
      Setting.mfm_enabled = mfm_enabled
      Setting.mfm_allow_composition = mfm_allow_composition
    end

    before do
      Setting.mfm_enabled = true
      Setting.mfm_allow_composition = true
    end

    it 'turns a plain status into MFM when MFM syntax is added' do
      status = PostStatusService.new.call(account, text: 'plain')

      service.call(status, account.id, text: '$[tada edited]')

      expect(status.reload).to have_attributes(mfm: true, mfm_text: '$[tada edited]')
    end

    it 'clears MFM when the syntax is removed' do
      status = PostStatusService.new.call(account, text: '$[tada first]')

      service.call(status, account.id, text: 'plain')

      expect(status.reload).to have_attributes(mfm: false, mfm_text: nil)
    end

    it 'does not switch to the MFM content type while composition is disabled' do
      status = PostStatusService.new.call(account, text: 'plain')
      Setting.mfm_allow_composition = false

      service.call(status, account.id, text: '$[x2 edited]', content_type: 'text/x-mfm')

      expect(status.reload).to have_attributes(content_type: 'text/plain', mfm: false)
    end

    it 'does not change sensitivity when no related option is submitted' do
      status = PostStatusService.new.call(account, text: 'plain', sensitive: true, media_ids: [])

      service.call(status, account.id, text: 'edited')

      expect(status.reload.sensitive).to be(true)
    end
  end
end
