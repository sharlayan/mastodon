import { describe, expect, it } from 'vitest';

import {
  pageDocumentPlainText,
  pageDocumentTextOnlyLength,
} from './plain_text';

describe('pageDocumentPlainText', () => {
  it('removes MFM document syntax while preserving visible text', () => {
    expect(
      pageDocumentPlainText(
        '$[x2 hello] **bold** [label](https://example.com) `code`',
        'mfm',
      ),
    ).toBe('hello bold label code');
  });

  it('removes Markdown and embedded HTML syntax', () => {
    expect(
      pageDocumentPlainText(
        '# Heading\n\n**bold** [label](https://example.com) <em>text</em>',
        'markdown',
      ),
    ).toBe('Heading\n\nbold label text');
  });

  it('excludes formatting syntax and whitespace from the text-only count', () => {
    expect(
      pageDocumentTextOnlyLength(
        '# Heading\n\n**bold text**\t한 글　字',
        'markdown',
      ),
    ).toBe(18);
  });
});
