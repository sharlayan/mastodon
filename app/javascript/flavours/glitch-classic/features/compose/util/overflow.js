import { length, substring } from 'stringz';

import { urlRegex } from './url_regex';

const URL_PLACEHOLDER_LENGTH = 23;

function buildCountableMap(text) {
  let inter = '';
  const map1 = [];
  let last = 0;
  let m;

  urlRegex.lastIndex = 0;

  while ((m = urlRegex.exec(text)) !== null) {
    const pre = m[2] ?? '';
    const bodyStart = m.index + pre.length;
    const bodyEnd = m.index + m[0].length;

    for (let i = last; i < bodyStart; i++) {
      inter += text[i];
      map1.push(i);
    }

    for (let k = 0; k < URL_PLACEHOLDER_LENGTH; k++) {
      inter += 'x';
      map1.push(bodyStart);
    }

    last = bodyEnd;

    if (m[0].length === 0) {
      urlRegex.lastIndex += 1;
    }
  }

  for (let i = last; i < text.length; i++) {
    inter += text[i];
    map1.push(i);
  }

  map1.push(text.length);

  let out = '';
  const map2 = [];
  last = 0;

  const mentionRe = /(^|[^/\w])@(([a-z0-9_]+)@[a-z0-9.-]+[a-z0-9]+)/gi;

  while ((m = mentionRe.exec(inter)) !== null) {
    const l1 = (m[1] ?? '').length;
    const matchStart = m.index;

    for (let i = last; i < matchStart; i++) {
      out += inter[i];
      map2.push(i);
    }

    for (let i = 0; i < l1; i++) {
      out += inter[matchStart + i];
      map2.push(matchStart + i);
    }

    out += '@';
    map2.push(matchStart + l1);

    const userStart = matchStart + l1 + 1;

    for (let i = 0; i < m[3].length; i++) {
      out += inter[userStart + i];
      map2.push(userStart + i);
    }

    last = matchStart + m[0].length;
  }

  for (let i = last; i < inter.length; i++) {
    out += inter[i];
    map2.push(i);
  }

  const map = map2.map((interIdx) => map1[interIdx] ?? text.length);
  map.push(text.length);

  return { countable: out, map };
}

export function overflowStart(text, max) {
  if (!text) {
    return -1;
  }

  const { countable, map } = buildCountableMap(text);

  if (length(countable) <= max) {
    return -1;
  }

  if (max <= 0) {
    return 0;
  }

  const cutCodeUnit = substring(countable, 0, max).length;

  return map[cutCodeUnit] ?? text.length;
}
