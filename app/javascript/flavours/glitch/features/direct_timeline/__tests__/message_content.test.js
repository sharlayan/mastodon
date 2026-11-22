import { fromJS } from 'immutable';

import {
  customEmojiOnlyCount,
  stripLeadingHandlesFromText,
  stripLeadingMentions,
  withoutLeadingHandles,
} from '../message_content';

const mention =
  '<span class="h-card"><a href="https://example.com/@alice" class="u-url mention">@<span>alice</span></a></span>';
const status = (contentHtml, extra = {}) =>
  fromJS({
    contentHtml,
    emojis: [{ shortcode: 'blob' }, { shortcode: 'cat_2' }],
    ...extra,
  });

describe('DM message content', () => {
  it('removes leading handles, including dotted usernames and line breaks', () => {
    expect(stripLeadingMentions(`<p>${mention} hello</p>`)).toBe('<p>hello</p>');
    expect(stripLeadingMentions(`<p>${mention}<br>hello</p>`)).toBe('<p>hello</p>');
    expect(stripLeadingMentions('<p>@al.ice-b@example.co.kr hello</p>')).toBe('<p>hello</p>');
    expect(stripLeadingHandlesFromText('@al.ice @bob@example.com hello')).toBe('hello');
    expect(stripLeadingMentions(`<p>${mention}</p><p>hello</p>`)).toBe('<p>hello</p>');
  });

  it('keeps handles that are part of the message', () => {
    const html = `<p>hello ${mention}</p>`;

    expect(stripLeadingMentions(html)).toBe(html);
    expect(stripLeadingHandlesFromText('@alice. hello')).toBe('@alice. hello');
  });

  it('keeps a message that only contains a handle', () => {
    const html = `<p>${mention}</p>`;

    expect(withoutLeadingHandles(status(html)).get('contentHtml')).toBe(html);
  });

  it('counts messages made only of known custom emojis', () => {
    const count = (html, extra) =>
      customEmojiOnlyCount(withoutLeadingHandles(status(html, extra)));

    expect(count(`<p>${mention} :blob:</p>`)).toBe(1);
    expect(count('<p>:blob: :cat_2:</p>')).toBe(2);
    expect(count('<p>:blob::cat_2:<br>:blob:</p><p>:cat_2:</p>')).toBe(4);
  });

  it('keeps the bubble for anything other than custom emojis', () => {
    const count = (html, extra) => customEmojiOnlyCount(status(html, extra));

    expect(count('<p>:blob: hello</p>')).toBe(0);
    expect(count('<p>:unknown:</p>')).toBe(0);
    expect(count('<p>😀</p>')).toBe(0);
    expect(count('<p><a href="https://example.com">:blob:</a></p>')).toBe(0);
    expect(count('<p>:blob:</p>', { mfm: true, mfm_text: '$[spin :blob:]' })).toBe(0);
    expect(count('<p>:blob:</p>', { mfm: true, mfm_text: ':blob:' })).toBe(1);
  });
});
