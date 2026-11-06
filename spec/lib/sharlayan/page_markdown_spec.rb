# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::PageMarkdown do
  describe '.to_html' do
    it 'renders Markdown with the advanced text formatter' do
      expect(described_class.to_html('**bold**')).to eq(AdvancedTextFormatter.new('**bold**', content_type: 'text/markdown').to_s)
    end

    it 'reuses the rendered HTML for the same source text' do
      allow(AdvancedTextFormatter).to receive(:new).and_call_original

      first = described_class.to_html('# Title')
      second = described_class.to_html('# Title')

      expect(second).to eq(first)
      expect(AdvancedTextFormatter).to have_received(:new).once
    end

    it 'renders different source text separately' do
      expect(described_class.to_html('*one*')).to_not eq(described_class.to_html('*two*'))
    end

    it 'treats nil as an empty document' do
      expect { described_class.to_html(nil) }.to_not raise_error
    end
  end

  describe 'page serialization' do
    it 'renders Markdown blocks through the shared cache for REST and Misskey responses' do
      page = Fabricate(:page, content: [{ 'id' => 'body', 'type' => 'text', 'format' => 'markdown', 'text' => '**cached**' }])
      allow(described_class).to receive(:to_html).and_call_original

      rest_block = REST::PageSerializer.new(page).as_json[:content].first
      misskey_block = MisskeyCompat::PageSerializer.serialize(page)[:content].first

      expect(rest_block['html']).to include('<strong>cached</strong>')
      expect(misskey_block['text']).to eq('cached')
      expect(described_class).to have_received(:to_html).with('**cached**').twice
    end
  end
end
