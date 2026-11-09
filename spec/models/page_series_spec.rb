# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PageSeries do
  let(:account) { Fabricate(:account) }
  let(:series) { Fabricate(:page_series, account: account) }

  def chat_media_attachment(owner)
    room = ChatConversation.create!(conversation_type: :group, title: 'Room', owner_account: owner)
    room.memberships.create!(account: owner, role: :owner)
    Fabricate(:media_attachment, account: owner, status: nil).tap do |media|
      room.messages.create!(account: owner, text: 'sent').media_attachments << media
    end
  end

  it 'generates an ID when persisted without one, normalizes its title and description and defaults to being displayed' do
    normalized = Fabricate.build(:page_series, account: account, title: '  Guides  ', description: '  A collection  ')

    expect(described_class.create!(account: account, title: 'Generated ID')).to be_persisted
    expect(normalized).to be_valid
    expect(normalized).to have_attributes(title: 'Guides', description: 'A collection')
    expect(series).to be_displayed
  end

  it 'uses the oldest public page as its entry page when no main page is set' do
    newer_page = Fabricate(:page, account: account, page_series: series, created_at: 1.day.ago)
    oldest_page = Fabricate(:page, account: account, page_series: series, created_at: 2.days.ago)
    Fabricate(:page, account: account, page_series: series, visibility: 'private', created_at: 3.days.ago)

    expect(series.reload.entry_page).to eq(oldest_page)

    series.update!(main_page: newer_page)

    expect(series.entry_page).to eq(newer_page)
  end

  it 'rejects a main page from another series or account, or one that does not exist' do
    expect(series.update(main_page: Fabricate(:page))).to be false
    expect(series.errors.of_kind?(:main_page, :invalid)).to be true

    expect(series.update(main_page_id: Page.maximum(:id).to_i + 1000)).to be false
    expect(series.errors.of_kind?(:main_page, :invalid)).to be true
  end

  it 'accepts only existing cover media owned by the same account and not sent in a chat message' do
    own_cover = Fabricate(:media_attachment, account: account)
    other_cover = Fabricate(:media_attachment)

    expect(series.update(cover_media_attachment: own_cover)).to be true
    expect(series.update(cover_media_attachment: other_cover)).to be false
    expect(series.errors.of_kind?(:cover_media_attachment, :invalid)).to be true

    expect(series.update(cover_media_attachment_id: MediaAttachment.maximum(:id).to_i + 1000)).to be false
    expect(series.errors.of_kind?(:cover_media_attachment, :invalid)).to be true

    expect(series.update(cover_media_attachment: chat_media_attachment(account))).to be false
    expect(series.errors.of_kind?(:cover_media_attachment, :invalid)).to be true
  end

  it 'clears the main page when that page leaves the series or is no longer public' do
    leaving_page = Fabricate(:page, account: account, page_series: series)
    series.update!(main_page: leaving_page)

    leaving_page.update!(page_series: nil)

    expect(series.reload.main_page).to be_nil

    hidden_page = Fabricate(:page, account: account, page_series: series)
    series.update!(main_page: hidden_page)

    hidden_page.update!(visibility: 'private')

    expect(series.reload.main_page).to be_nil
  end
end
