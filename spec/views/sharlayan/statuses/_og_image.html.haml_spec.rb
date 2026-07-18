# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'statuses/_og_image.html.haml' do
  let(:account) { Fabricate(:account) }
  let(:status) { Fabricate(:status, account:) }
  let(:drive_file) { account.drive_files.create!(file: attachment_fixture('attachment.jpg')) }
  let(:media) do
    drive_file.build_pointer(account).tap do |pointer|
      pointer.status = status
      pointer.save!
    end
  end

  it 'renders Drive resolver URLs for pointer attachments' do
    media

    render partial: 'statuses/og_image', locals: { account:, status: }

    expect(rendered).to include("/drive_media/#{media.drive_access_key}/original")
    expect(rendered).to include('property="og:image"')
  end
end
