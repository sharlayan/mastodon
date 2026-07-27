# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BoardAnnouncementFormatter do
  subject { described_class.new(text).to_html }

  context 'with blank text' do
    let(:text) { '' }

    it { is_expected.to eq '' }
  end

  context 'when a blockquote directly follows a paragraph line' do
    let(:text) { "paragraph\n> quoted" }

    it 'renders the blockquote as its own block' do
      expect(subject).to eq '<p>paragraph</p><blockquote><p>quoted</p></blockquote>'
    end
  end

  context 'with a single line break' do
    let(:text) { "first\nsecond" }

    it 'renders a hard break' do
      expect(subject).to eq '<p>first<br>second</p>'
    end
  end

  context 'with a GFM table' do
    let(:text) { "| a | b |\n|---|---|\n| 1 | 2 |" }

    it 'renders table markup' do
      expect(subject).to include '<table>'
      expect(subject).to include '<th>a</th>'
      expect(subject).to include '<td>2</td>'
    end
  end

  context 'with strikethrough and autolinks' do
    let(:text) { '~~gone~~ https://example.com/' }

    it 'renders both extensions' do
      expect(subject).to include '<del>gone</del>'
      expect(subject).to include '<a href="https://example.com/"'
    end
  end

  context 'with a task list' do
    let(:text) { "- [ ] todo\n- [x] done" }

    it 'renders disabled checkboxes with GitHub classes' do
      expect(subject).to include '<ul class="contains-task-list">'
      expect(subject).to include '<li class="task-list-item"><input type="checkbox" disabled="disabled">'
      expect(subject).to include '<input type="checkbox" checked="" disabled="disabled">'
    end
  end

  context 'with a fenced code block' do
    let(:text) { "```ruby\nputs 1\nputs 2\n```" }

    it 'keeps the language class and inner newlines' do
      expect(subject).to eq %(<pre><code class="language-ruby">puts 1\nputs 2\n</code></pre>)
    end
  end

  context 'with a GitHub alert' do
    let(:text) { "> [!WARNING]\n> be careful" }

    it 'renders an alert box with a title' do
      expect(subject).to include '<div class="markdown-alert markdown-alert-warning">'
      expect(subject).to include '<p class="markdown-alert-title">Warning</p>'
      expect(subject).to include '<p>be careful</p>'
      expect(subject).to_not include '[!WARNING]'
    end
  end

  context 'with an unknown alert marker' do
    let(:text) { "> [!SPOILER]\n> nope" }

    it 'keeps the blockquote untouched' do
      expect(subject).to include '<blockquote>'
      expect(subject).to include '[!SPOILER]'
    end
  end

  context 'with inline HTML' do
    let(:text) { '<mark style="color: red">kept</mark> <details><summary>s</summary>body</details>' }

    it 'keeps allowed elements and properties' do
      expect(subject).to include '<mark style="color: red">kept</mark>'
      expect(subject).to include '<details><summary>s</summary>body</details>'
    end
  end

  context 'with dangerous HTML' do
    let(:text) { '<script>alert(1)</script><div onclick="alert(2)" style="position: fixed">x</div><input type="text" name="y">' }

    it 'strips scripts, event handlers, disallowed properties and inputs' do
      expect(subject).to_not include 'script'
      expect(subject).to_not include 'onclick'
      expect(subject).to_not include 'position'
      expect(subject).to_not include '<input'
      expect(subject).to include '<div>x</div>'
    end
  end

  context 'with a javascript link' do
    let(:text) { '[click](javascript:alert(1))' }

    it 'removes the link' do
      expect(subject).to_not include '<a'
      expect(subject).to include 'click'
    end
  end

  context 'with an image' do
    let(:text) { '![pic](https://example.com/a.png)' }

    it 'keeps the image' do
      expect(subject).to include '<img src="https://example.com/a.png" alt="pic">'
    end
  end

  context 'with an external link' do
    let(:text) { '[example](https://example.com/)' }

    it 'adds link attributes' do
      expect(subject).to include 'rel="nofollow noopener"'
      expect(subject).to include 'target="_blank"'
    end
  end

  context 'with nested block markup' do
    let(:text) { "> - item\n>   - nested" }

    it 'does not leave cosmetic newlines outside code blocks' do
      expect(subject).to_not include "\n"
    end
  end
end
