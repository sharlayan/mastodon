import { marked } from 'marked';
import * as mfm from 'mfm-js';
import type { MfmNode } from 'mfm-js';

export const pageDocumentPlainText = (
  source: string,
  format: 'mfm' | 'markdown',
) => {
  if (format === 'markdown') {
    const html = marked.parse(source);
    const withBlockBreaks = html
      .replace(/<br\s*\/?>/giu, '\n')
      .replace(
        /<\/(?:blockquote|div|h[1-6]|li|ol|p|pre|table|tr|ul)>/giu,
        '\n',
      );
    const document = new DOMParser().parseFromString(
      withBlockBreaks,
      'text/html',
    );
    document.querySelectorAll('script, style').forEach((node) => {
      node.remove();
    });
    return document.body.textContent.replace(/\n+$/u, '');
  }

  try {
    return mfm.parse(source).map(mfmNodeText).join('');
  } catch {
    return source;
  }
};

const mfmNodeText = (node: MfmNode): string => {
  if (node.children?.length) {
    return node.children.map(mfmNodeText).join('');
  }

  switch (node.type) {
    case 'text':
      return node.props.text;
    case 'unicodeEmoji':
      return node.props.emoji;
    case 'emojiCode':
      return `:${node.props.name}:`;
    case 'mention':
      return node.props.acct;
    case 'hashtag':
      return `#${node.props.hashtag}`;
    case 'url':
      return node.props.url;
    case 'inlineCode':
    case 'blockCode':
      return node.props.code;
    case 'mathInline':
    case 'mathBlock':
      return node.props.formula;
    case 'search':
      return node.props.content;
    default:
      return '';
  }
};
