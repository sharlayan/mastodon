# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BoardAnnouncementFormatter do
  def html(text)
    described_class.new(text).to_html
  end

  it 'renders blank text, block separation, hard breaks and code blocks without cosmetic newlines' do
    expect(html('')).to eq ''
    expect(html("paragraph\n> quoted")).to eq '<p>paragraph</p><blockquote><p>quoted</p></blockquote>'
    expect(html("first\nsecond")).to eq '<p>first<br>second</p>'
    expect(html("```ruby\nputs 1\nputs 2\n```")).to eq %(<pre><code class="language-ruby">puts 1\nputs 2\n</code></pre>)
    expect(html("> - item\n>   - nested")).to_not include "\n"
  end

  it 'renders GFM tables, strikethrough, autolinks and task lists' do
    table = html("| a | b |\n|---|---|\n| 1 | 2 |")
    extensions = html('~~gone~~ https://example.com/')
    task_list = html("- [ ] todo\n- [x] done")

    expect(table).to include('<table>', '<th>a</th>', '<td>2</td>')
    expect(extensions).to include('<del>gone</del>', '<a href="https://example.com/"')
    expect(task_list).to include(
      '<ul class="contains-task-list">',
      '<li class="task-list-item"><input type="checkbox" disabled="disabled">',
      '<input type="checkbox" checked="" disabled="disabled">'
    )
  end

  it 'renders known GitHub alerts with a title and leaves unknown alert markers as blockquotes' do
    alert = html("> [!WARNING]\n> be careful")
    unknown = html("> [!SPOILER]\n> nope")

    expect(alert).to include(
      '<div class="markdown-alert markdown-alert-warning">',
      '<p class="markdown-alert-title">Warning</p>',
      '<p>be careful</p>'
    )
    expect(alert).to_not include '[!WARNING]'
    expect(unknown).to include('<blockquote>', '[!SPOILER]')
  end

  it 'keeps allowed inline HTML and strips scripts, event handlers, disallowed properties, inputs and javascript links' do
    allowed = html('<mark style="color: red">kept</mark> <details><summary>s</summary>body</details>')
    dangerous = html('<script>alert(1)</script><div onclick="alert(2)" style="position: fixed">x</div><input type="text" name="y">')
    javascript_link = html('[click](javascript:alert(1))')

    expect(allowed).to include('<mark style="color: red">kept</mark>', '<details><summary>s</summary>body</details>')
    expect(dangerous).to_not include 'script'
    expect(dangerous).to_not include 'onclick'
    expect(dangerous).to_not include 'position'
    expect(dangerous).to_not include '<input'
    expect(dangerous).to include '<div>x</div>'
    expect(javascript_link).to_not include '<a'
    expect(javascript_link).to include 'click'
  end

  it 'keeps images and adds attributes to external links' do
    expect(html('![pic](https://example.com/a.png)')).to include '<img src="https://example.com/a.png" alt="pic">'
    expect(html('[example](https://example.com/)')).to include('rel="nofollow noopener"', 'target="_blank"')
  end
end
