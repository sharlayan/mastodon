# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MisskeyCompatMediaMd5Worker do
  let(:media) { Fabricate(:media_attachment, file: attachment_fixture('attachment.jpg')) }

  it 'stores the md5 of the original file without dropping other metadata' do
    media.update_column(:file_meta, { 'focus' => { 'x' => 0.5, 'y' => 0.5 } })

    described_class.new.perform(media.id)

    meta = media.reload.file_meta
    expect(meta['md5']).to eq(Digest::MD5.file(media.file.path(:original)).hexdigest)
    expect(meta['focus']).to eq({ 'x' => 0.5, 'y' => 0.5 })
  end

  it 'ignores missing media attachments' do
    expect { described_class.new.perform(-1) }.to_not raise_error
  end
end
