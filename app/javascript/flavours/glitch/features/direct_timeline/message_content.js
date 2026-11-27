const parser = new DOMParser();

const handleTokenRegex = /^\s*@\w(?:[\w.-]*\w)?(?:@[\p{L}\p{N}.-]+)?(?=\s|$)/u;
const emojiOnlyRegex = /^(?::[\w@.-]+:\s*)+$/;
const shortcodeRegex = /:([\w@.-]+):/g;

const isMention = (node) =>
  node.nodeType === Node.ELEMENT_NODE &&
  (node.matches('a.mention') ||
    node.classList.contains('h-card') ||
    node.classList.contains('recipients-inline'));

const isBreak = (node) =>
  node.nodeType === Node.ELEMENT_NODE && node.tagName === 'BR';

const isBlankText = (node) =>
  node.nodeType === Node.TEXT_NODE && node.textContent.trim() === '';

const stripHandleTokens = (text) => {
  let result = text;
  let removed = false;

  while (handleTokenRegex.test(result)) {
    result = result.replace(handleTokenRegex, '');
    removed = true;
  }

  return { text: result.replace(/^\s+/, ''), removed };
};

export const stripLeadingMentions = (html) => {
  if (!html) {
    return html;
  }

  const doc = parser.parseFromString(html, 'text/html');
  const first = doc.body.firstElementChild;
  const container = first && first.tagName === 'P' ? first : doc.body;

  let node = container.firstChild;
  let removedMention = false;

  while (node) {
    const next = node.nextSibling;

    if (isMention(node)) {
      removedMention = true;
      node.remove();
      node = next;
      continue;
    }

    if (isBlankText(node) || (removedMention && isBreak(node))) {
      node.remove();
      node = next;
      continue;
    }

    if (node.nodeType === Node.TEXT_NODE) {
      const { text, removed } = stripHandleTokens(node.textContent);

      if (removed) {
        removedMention = true;
      }

      if (removedMention) {
        node.textContent = text;
      }

      if (removed && text === '') {
        node.remove();
        node = next;
        continue;
      }
    }

    break;
  }

  if (!removedMention) {
    return html;
  }

  if (container !== doc.body && container.childNodes.length === 0) {
    container.remove();
  }

  return doc.body.innerHTML;
};

export const stripLeadingHandlesFromText = (value) => {
  if (!value) {
    return value;
  }

  const { text, removed } = stripHandleTokens(value);

  return removed ? text : value;
};

const htmlIsEmpty = (html) => {
  if (!html) {
    return true;
  }

  const doc = parser.parseFromString(html, 'text/html');

  return (doc.body.textContent || '').trim() === '';
};

export const withoutLeadingHandles = (status) => {
  if (!status) {
    return status;
  }

  let next = status;
  const html = status.get('contentHtml');
  const translatedHtml = status.getIn(['translation', 'contentHtml']);
  const mfmText = status.get('mfm_text');

  if (html) {
    const stripped = stripLeadingMentions(html);

    if (!htmlIsEmpty(stripped)) {
      next = next.set('contentHtml', stripped);
    }
  }

  if (translatedHtml) {
    const stripped = stripLeadingMentions(translatedHtml);

    if (!htmlIsEmpty(stripped)) {
      next = next.setIn(['translation', 'contentHtml'], stripped);
    }
  }

  if (mfmText) {
    const stripped = stripLeadingHandlesFromText(mfmText);

    if (stripped.trim() !== '') {
      next = next.set('mfm_text', stripped);
    }
  }

  return next;
};

export const plainStatusWithoutLeadingHandles = (status) => {
  if (!status) {
    return status;
  }

  const next = { ...status };

  if (status.contentHtml) {
    const stripped = stripLeadingMentions(status.contentHtml);

    if (!htmlIsEmpty(stripped)) {
      next.contentHtml = stripped;
    }
  }

  if (status.translation?.contentHtml) {
    const stripped = stripLeadingMentions(status.translation.contentHtml);

    if (!htmlIsEmpty(stripped)) {
      next.translation = { ...status.translation, contentHtml: stripped };
    }
  }

  if (status.mfm_text) {
    const stripped = stripLeadingHandlesFromText(status.mfm_text);

    if (stripped.trim() !== '') {
      next.mfm_text = stripped;
    }
  }

  return next;
};

const countKnownShortcodes = (text, shortcodes) => {
  const trimmed = text.trim();

  if (!emojiOnlyRegex.test(trimmed)) {
    return 0;
  }

  const tokens = Array.from(trimmed.matchAll(shortcodeRegex), (match) => match[1]);

  return tokens.every((code) => shortcodes.has(code)) ? tokens.length : 0;
};

export const customEmojiOnlyCount = (status) => {
  const translatedHtml = status.getIn(['translation', 'contentHtml']);
  const html = translatedHtml || status.get('contentHtml');

  if (!html) {
    return 0;
  }

  const doc = parser.parseFromString(html, 'text/html');

  if (doc.body.querySelector(':not(p, br, span)')) {
    return 0;
  }

  const shortcodes = new Set(
    (status.get('emojis') ?? []).map((emoji) => emoji.get('shortcode')),
  );
  const count = countKnownShortcodes(doc.body.textContent || '', shortcodes);
  const mfmText = status.get('mfm_text');

  if (count > 0 && status.get('mfm') && mfmText && !translatedHtml) {
    return countKnownShortcodes(mfmText, shortcodes);
  }

  return count;
};
