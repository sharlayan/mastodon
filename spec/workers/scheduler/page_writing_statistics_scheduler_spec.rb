# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scheduler::PageWritingStatisticsScheduler do
  let(:account) { Fabricate(:account) }

  it 'backfills missing stored counts without inventing historical activity' do
    page = Fabricate(:page, account: account, summary: 'summary')
    page.update_column(:text_characters_count, nil)
    original_statistic = PageDailyStatistic.find_by!(account: account).attributes

    described_class.new.perform

    expect(page.reload.text_characters_count).to eq(7)
    expect(PageDailyStatistic.find_by!(account: account).attributes).to include(
      original_statistic.slice('characters_delta', 'pages_created_count', 'pages_updated_count')
    )
  end

  it 'repairs a recently changed count and records the missed update delta' do
    page = Fabricate(:page, account: account, content: [{ type: 'text', text: 'old' }])
    page.update_columns(content: [{ type: 'text', text: 'new text' }], updated_at: Time.current)

    described_class.new.perform

    expect(page.reload.text_characters_count).to eq(7)
    expect(PageDailyStatistic.find_by!(account: account)).to have_attributes(
      characters_delta: 7,
      pages_created_count: 1,
      pages_updated_count: 1
    )
  end
end
