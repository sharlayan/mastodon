# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Drive media', :attachment_processing do
  let(:account) { Fabricate(:account) }
  let(:drive_file) { DriveFile.create!(account: account, file: attachment_fixture('600x400.png')) }
  let(:pointer) { drive_file.build_pointer(account).tap(&:save!) }

  before do
    Setting.drive_enabled = false
  end

  it 'serves original files from local storage while disabled' do
    get drive_media_path(pointer.drive_access_key, :original)

    expect(response).to have_http_status(200)
    expect(response.media_type).to eq('image/png')
    expect(response.body.b).to eq(File.binread(drive_file.file.path(:original)))
  end

  it 'serves previews from local storage with their actual format' do
    get drive_media_path(pointer.drive_access_key, :small)

    expect(response).to have_http_status(200)
    expect(response.media_type).to eq('image/png')
    expect(File).to exist(drive_file.file.path(:small))
    expect(response.body.b).to eq(File.binread(drive_file.file.path(:small)))
  end

  it 'serves a byte range so that media can be sought' do
    get drive_media_path(pointer.drive_access_key, :original), headers: { 'Range' => 'bytes=0-9' }

    expect(response).to have_http_status(206)
    expect(response.headers['Content-Range']).to eq("bytes 0-9/#{File.size(drive_file.file.path(:original))}")
    expect(response.body.b).to eq(File.binread(drive_file.file.path(:original), 10))
  end

  it 'serves media inline under its display name' do
    drive_file.update!(display_name: '설정 자료.png')

    get drive_media_path(pointer.drive_access_key, :original)

    expect(response.headers['Content-Disposition']).to start_with('inline')
    expect(response.headers['Content-Disposition']).to include('%EC%84%A4%EC%A0%95')
  end

  it 'forces non-media Drive files to download without content sniffing' do
    Setting.drive_allowed_extensions = 'txt'
    file = DriveFile.create!(account: account, file: attachment_fixture('bookmark-imports.txt'))
    file_pointer = file.build_pointer(account).tap(&:save!)

    get drive_media_path(file_pointer.drive_access_key, :original)

    expect(response).to have_http_status(200)
    expect(response.headers['Content-Disposition']).to start_with('attachment')
    expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
    expect(response.headers['Content-Security-Policy']).to eq("default-src 'none'; sandbox")
    expect(response.body).to eq(File.binread(file.file.path(:original)))
  end

  it 'hands local files to the web server when a sendfile header is configured' do
    allow(Rails.configuration.action_dispatch).to receive(:x_sendfile_header).and_return('X-Accel-Redirect')

    get drive_media_path(pointer.drive_access_key, :original)

    expect(response).to have_http_status(200)
    expect(response.media_type).to eq('image/png')
  end

  it 'redirects public S3 files to their object URL' do
    pointer
    stub_object_storage
    stub_drive_attachment(:url, :original, 'https://public.example/drive/object.png')

    ClimateControl.modify S3_ENABLED: 'true', S3_PERMISSION: 'public-read' do
      get drive_media_path(pointer.drive_access_key, :original)
    end

    expect(response).to redirect_to('https://public.example/drive/object.png')
  end

  it 'redirects private S3 files to an expiring object URL' do
    pointer
    stub_object_storage
    stub_drive_attachment(:expiring_url, 3600, :original, 'https://private.example/drive/signed-object.png')

    ClimateControl.modify S3_ENABLED: 'true', S3_PERMISSION: '' do
      get drive_media_path(pointer.drive_access_key, :original)
    end

    expect(response).to redirect_to('https://private.example/drive/signed-object.png')
  end

  def stub_object_storage
    allow(Paperclip::Attachment.default_options).to receive(:[]).and_call_original
    allow(Paperclip::Attachment.default_options).to receive(:[]).with(:storage).and_return(:s3)
  end

  it 'does not resolve a numeric media attachment ID as an access key' do
    get drive_media_path(pointer.id, :original)

    expect(response).to have_http_status(404)
  end

  def stub_drive_attachment(method_name, *arguments, result)
    allow(Paperclip::Attachment).to receive(:new).and_wrap_original do |original, *constructor_arguments|
      original.call(*constructor_arguments).tap do |attachment|
        allow(attachment).to receive(method_name).with(*arguments).and_return(result) if constructor_arguments.first == :file
      end
    end
  end
end
