// The plain-text transformation rules are ported from Misskey
// (https://github.com/misskey-dev/misskey, packages/misskey-js/src/nyaize.ts

import {
  catEnabled,
  catFederationEnabled,
  me,
  showCat,
  showFederatedCat,
} from 'flavours/glitch/initial_state';

const SKIP_TAGS = new Set(['a', 'code', 'pre']);

const KO_NA_OFFSET = 56;

export function catEffectsVisibleFor(
  acct: string | undefined,
  isCat: boolean | undefined,
): boolean {
  if (!catEnabled || !isCat) {
    return false;
  }

  const isGuest = !me;
  const isRemote = acct?.includes('@') ?? false;

  if (!isGuest && !showCat) {
    return false;
  }

  if (isRemote && !isGuest && !(catFederationEnabled && showFederatedCat)) {
    return false;
  }

  return true;
}

function nyaifyPlain(text: string): string {
  return text
    .replace(/な/g, 'にゃ')
    .replace(/ナ/g, 'ニャ')
    .replace(/ﾅ/g, 'ﾆｬ')
    .replace(/(?<=n)a/gi, (match) => (match === 'A' ? 'YA' : 'ya'))
    .replace(/(?<=morn)ing/gi, (match) => (match === 'ING' ? 'YAN' : 'yan'))
    .replace(/(?<=every)one/gi, (match) => (match === 'ONE' ? 'NYAN' : 'nyan'))
    .replace(/[나-낳]/g, (match) =>
      String.fromCodePoint((match.codePointAt(0) ?? 0) + KO_NA_OFFSET),
    )
    .replace(/다(?=$|[.!? ])/gu, '다냥')
    .replace(/야(?=$|[? ])/gu, '냥');
}

function nyaifyTextSegment(text: string): string {
  return text
    .split(/(:[a-zA-Z0-9_]+:)/)
    .map((part, index) => (index % 2 === 1 ? part : nyaifyPlain(part)))
    .join('');
}

export function nyaifyHtml(html: string): string {
  let skipDepth = 0;

  return html.replace(
    /(<[^>]+>)|([^<]+)/g,
    (_match, tag: string, text: string) => {
      if (tag) {
        const parsed = /^<\s*(\/?)\s*([a-zA-Z0-9]+)/.exec(tag);
        const name = parsed?.[2]?.toLowerCase();

        if (name && SKIP_TAGS.has(name)) {
          if (parsed?.[1]) {
            if (skipDepth > 0) {
              skipDepth -= 1;
            }
          } else if (!/\/>\s*$/.test(tag)) {
            skipDepth += 1;
          }
        }

        return tag;
      }

      return skipDepth > 0 ? text : nyaifyTextSegment(text);
    },
  );
}
