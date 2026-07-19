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

  describe '#apply_sharlayan_immediate_attributes' do
    it 'keeps edited MFM source synchronized with status text' do
      status = instance_double(Status, mfm?: true, text: '$[tada edited]')
      allow(status).to receive(:mfm_text=)
      service.instance_variable_set(:@status, status)
      service.instance_variable_set(:@options, { text: '$[tada edited]' })

      service.send(:apply_sharlayan_immediate_attributes)

      expect(status).to have_received(:mfm_text=).with('$[tada edited]')
    end

    it 'does not change sensitivity when no related option is submitted' do
      status = instance_double(Status, mfm?: false, text: 'plain')
      allow(status).to receive(:mfm_text=)
      allow(status).to receive(:sensitive=)
      service.instance_variable_set(:@status, status)
      service.instance_variable_set(:@options, { text: 'plain' })

      service.send(:apply_sharlayan_immediate_attributes)

      expect(status).to have_received(:mfm_text=).with(nil)
      expect(status).to_not have_received(:sensitive=)
    end
  end
end
