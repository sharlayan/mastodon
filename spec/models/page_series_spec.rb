# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PageSeries do
  let(:account) { Fabricate(:account) }
  let(:series) { Fabricate(:page_series, account: account) }

  it 'generates an ID when persisted without one' do
    expect(described_class.create!(account: account, title: 'Generated ID')).to be_persisted
  end

  it 'normalizes its title and description' do
    series = Fabricate.build(:page_series, account: account, title: '  Guides  ', description: '  A collection  ')

    expect(series).to be_valid
    expect(series).to have_attributes(title: 'Guides', description: 'A collection')
  end

  it 'accepts a public page from the same series as its main page' do
    page = Fabricate(:page, account: account, page_series: series)

    expect(series.update(main_page: page)).to be true
  end

  it 'rejects a main page from another series or account' do
    other_page = Fabricate(:page)

    expect(series.update(main_page: other_page)).to be false
    expect(series.errors.of_kind?(:main_page, :invalid)).to be true
  end

  it 'clears the main page when that page leaves the series' do
    page = Fabricate(:page, account: account, page_series: series)
    series.update!(main_page: page)

    page.update!(page_series: nil)

    expect(series.reload.main_page).to be_nil
  end

  it 'clears the main page when it is no longer public' do
    page = Fabricate(:page, account: account, page_series: series)
    series.update!(main_page: page)

    page.update!(visibility: 'private')

    expect(series.reload.main_page).to be_nil
  end
end
