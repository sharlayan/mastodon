# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MfmHtmlConverter do
  describe '.convert' do
    it 'converts inline markdown and escapes HTML in inline code' do
      expect(described_class.convert('**bold text**')).to eq('<b>bold text</b>')
      expect(described_class.convert('*italic*')).to eq('<i>italic</i>')
      expect(described_class.convert('_italic_')).to eq('<i>italic</i>')
      expect(described_class.convert('~~strikethrough~~')).to eq('<del>strikethrough</del>')
      expect(described_class.convert('`code here`')).to eq('<code>code here</code>')
      expect(described_class.convert('`<script>`')).to eq('<code>&lt;script&gt;</code>')
    end

    it 'converts fenced code blocks and escapes HTML in them' do
      expect(described_class.convert("```\nsome code\n```")).to include('<pre><code>', 'some code', '</code></pre>')
      expect(described_class.convert("```\n<script>\n```")).to include('&lt;script&gt;')
    end

    it 'converts center, small and blur functions' do
      expect(described_class.convert('$[center hello]')).to eq('<div style="text-align: center;">hello</div>')
      expect(described_class.convert('$[small text]')).to eq('<small>text</small>')
      expect(described_class.convert('$[blur hidden]')).to eq('<span>hidden</span>')
    end

    it 'renders unknown and animation functions as italic' do
      expect(described_class.convert('$[tada hello]')).to eq('<i>hello</i>')
      expect(described_class.convert('$[spin.speed=2s text]')).to eq('<i>text</i>')
    end

    it 'converts two-part ruby annotations and wraps single-part ruby in ruby tags' do
      expect(described_class.convert('$[ruby 漢字 かんじ]')).to eq('<ruby>漢字<rp>(</rp><rt>かんじ</rt><rp>)</rp></ruby>')
      expect(described_class.convert('$[ruby 漢字]')).to include('<ruby>', '</ruby>')
    end

    it 'converts unixtime to a time element and passes through non-positive timestamps' do
      expect(described_class.convert('$[unixtime 1609459200]')).to include('<time datetime=', '2021-01-01T00:00:00Z', '</time>')
      expect(described_class.convert('$[unixtime 0]')).to eq('0')
    end

    it 'returns an empty string for blank input' do
      expect(described_class.convert(nil)).to eq('')
      expect(described_class.convert('')).to eq('')
    end
  end

  describe '.convert_in_html' do
    it 'converts markdown and MFM functions while preserving existing HTML markup' do
      expect(described_class.convert_in_html('<p>**bold** text</p>')).to include('<b>bold</b>')
      expect(described_class.convert_in_html('<p>*italic* text</p>')).to include('<i>italic</i>')
      expect(described_class.convert_in_html('<p>~~strike~~</p>')).to include('<del>strike</del>')
      expect(described_class.convert_in_html('<p>$[center hello]</p>')).to include('<div style="text-align: center;">hello</div>')
      expect(described_class.convert_in_html('<p>hello <a href="https://example.com">link</a></p>')).to include('<a href="https://example.com">link</a>')
    end

    it 'does not rewrite MFM or emphasis syntax carried inside an attribute value' do
      mfm_html = '<p><a href="https://example.com/$[center.x autofocus onfocus=alert(1) z]" rel="nofollow noopener" target="_blank">link</a></p>'
      emphasis_html = '<p><a href="https://example.com/**a**" rel="nofollow noopener">link</a></p>'

      expect(described_class.convert_in_html(mfm_html)).to eq(mfm_html)
      expect(described_class.convert_in_html(emphasis_html)).to eq(emphasis_html)
    end

    it 'returns blank input as-is' do
      expect(described_class.convert_in_html('')).to be_blank
      expect(described_class.convert_in_html(nil)).to be_blank
    end
  end
end
