import { nyaifyHtml } from './nyaify';

describe('nyaifyHtml', () => {
  it('applies Japanese cat speak to plain text', () => {
    expect(nyaifyHtml('<p>こんな感じ</p>')).toBe('<p>こんにゃ感じ</p>');
  });

  it('applies English cat speak after "n"', () => {
    expect(nyaifyHtml('<p>banana</p>')).toBe('<p>banyanya</p>');
    expect(nyaifyHtml('<p>good morning everyone</p>')).toBe(
      '<p>good mornyan everynyan</p>',
    );
  });

  it('applies Korean cat speak', () => {
    expect(nyaifyHtml('<p>나는 고양이다.</p>')).toBe('<p>냐는 고양이다냥.</p>');
    expect(nyaifyHtml('<p>먹었다</p>')).toBe('<p>먹었다냥</p>');
  });

  it('leaves link, code and mention content untouched', () => {
    expect(nyaifyHtml('<p>na <a href="/tags/banana">#banana</a> na</p>')).toBe(
      '<p>nya <a href="/tags/banana">#banana</a> nya</p>',
    );
    expect(nyaifyHtml('<pre><code>banana()</code></pre>')).toBe(
      '<pre><code>banana()</code></pre>',
    );
  });

  it('leaves mention text nested inside an anchor untouched', () => {
    expect(
      nyaifyHtml(
        '<p>na <span class="h-card"><a href="https://example.com/@tanaka" class="u-url mention">@<span>tanaka</span></a></span> na</p>',
      ),
    ).toBe(
      '<p>nya <span class="h-card"><a href="https://example.com/@tanaka" class="u-url mention">@<span>tanaka</span></a></span> nya</p>',
    );
  });

  it('leaves a bare URL with cat-speak substrings untouched inside an anchor', () => {
    expect(
      nyaifyHtml(
        '<p><a href="https://example.com/banana/나라">https://example.com/banana/나라</a></p>',
      ),
    ).toBe(
      '<p><a href="https://example.com/banana/나라">https://example.com/banana/나라</a></p>',
    );
  });

  it('leaves custom emoji shortcodes untouched', () => {
    expect(nyaifyHtml('<p>na :banana: na</p>')).toBe('<p>nya :banana: nya</p>');
  });
});
