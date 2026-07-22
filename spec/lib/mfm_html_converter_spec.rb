# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MfmHtmlConverter do
  describe '.convert' do
    context 'with inline markdown' do
      it 'converts bold' do
        expect(described_class.convert('**bold text**')).to eq('<b>bold text</b>')
      end

      it 'converts italic with asterisk' do
        expect(described_class.convert('*italic*')).to eq('<i>italic</i>')
      end

      it 'converts italic with underscore' do
        expect(described_class.convert('_italic_')).to eq('<i>italic</i>')
      end

      it 'converts strikethrough' do
        expect(described_class.convert('~~strikethrough~~')).to eq('<del>strikethrough</del>')
      end

      it 'converts inline code' do
        expect(described_class.convert('`code here`')).to eq('<code>code here</code>')
      end

      it 'escapes HTML in inline code' do
        expect(described_class.convert('`<script>`')).to eq('<code>&lt;script&gt;</code>')
      end
    end

    context 'with block code' do
      it 'converts fenced code block' do
        expect(described_class.convert("```\nsome code\n```")).to include('<pre><code>', 'some code', '</code></pre>')
      end

      it 'escapes HTML in block code' do
        expect(described_class.convert("```\n<script>\n```")).to include('&lt;script&gt;')
      end
    end

    context 'with MFM functions' do
      it 'converts center' do
        expect(described_class.convert('$[center hello]')).to eq('<div style="text-align: center;">hello</div>')
      end

      it 'converts small' do
        expect(described_class.convert('$[small text]')).to eq('<small>text</small>')
      end

      it 'converts blur as span' do
        expect(described_class.convert('$[blur hidden]')).to eq('<span>hidden</span>')
      end

      it 'renders unknown functions as italic' do
        expect(described_class.convert('$[tada hello]')).to eq('<i>hello</i>')
      end

      it 'renders animation functions as italic fallback' do
        expect(described_class.convert('$[spin.speed=2s text]')).to eq('<i>text</i>')
      end

      it 'converts ruby annotation with two parts' do
        result = described_class.convert('$[ruby 漢字 かんじ]')
        expect(result).to eq('<ruby>漢字<rp>(</rp><rt>かんじ</rt><rp>)</rp></ruby>')
      end

      it 'wraps single-part ruby in ruby tags' do
        result = described_class.convert('$[ruby 漢字]')
        expect(result).to include('<ruby>', '</ruby>')
      end

      it 'converts unixtime to time element' do
        ts = 1_609_459_200 # 2021-01-01T00:00:00Z
        result = described_class.convert("$[unixtime #{ts}]")
        expect(result).to include('<time datetime=', '2021-01-01T00:00:00Z', '</time>')
      end

      it 'passes through unixtime content when timestamp is zero or negative' do
        result = described_class.convert('$[unixtime 0]')
        expect(result).to eq('0')
      end
    end

    context 'with blank input' do
      it 'returns empty string for nil' do
        expect(described_class.convert(nil)).to eq('')
      end

      it 'returns empty string for empty string' do
        expect(described_class.convert('')).to eq('')
      end
    end
  end

  describe '.convert_in_html' do
    it 'converts bold in HTML context' do
      html = '<p>**bold** text</p>'
      expect(described_class.convert_in_html(html)).to include('<b>bold</b>')
    end

    it 'converts italic in HTML context' do
      html = '<p>*italic* text</p>'
      expect(described_class.convert_in_html(html)).to include('<i>italic</i>')
    end

    it 'converts strikethrough in HTML context' do
      html = '<p>~~strike~~</p>'
      expect(described_class.convert_in_html(html)).to include('<del>strike</del>')
    end

    it 'converts MFM functions in HTML context' do
      html = '<p>$[center hello]</p>'
      expect(described_class.convert_in_html(html)).to include('<div style="text-align: center;">hello</div>')
    end

    it 'preserves existing HTML markup' do
      html = '<p>hello <a href="https://example.com">link</a></p>'
      result = described_class.convert_in_html(html)
      expect(result).to include('<a href="https://example.com">link</a>')
    end

    it 'does not rewrite MFM syntax carried inside an attribute value' do
      html = '<p><a href="https://example.com/$[center.x autofocus onfocus=alert(1) z]" rel="nofollow noopener" target="_blank">link</a></p>'

      expect(described_class.convert_in_html(html)).to eq(html)
    end

    it 'does not rewrite emphasis syntax carried inside an attribute value' do
      html = '<p><a href="https://example.com/**a**" rel="nofollow noopener">link</a></p>'

      expect(described_class.convert_in_html(html)).to eq(html)
    end

    it 'returns blank input as-is' do
      expect(described_class.convert_in_html('')).to be_blank
      expect(described_class.convert_in_html(nil)).to be_blank
    end
  end
end
