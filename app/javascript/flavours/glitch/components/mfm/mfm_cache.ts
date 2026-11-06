import { createLruCache } from './lru_cache';
import { MFM_FOLD_LENGTH_THRESHOLD } from './mfm_constants';
import { hasAnyMfmFn, hasSensitiveFoldTags } from './mfm_renderer';

export { createLruCache };

const foldCache = createLruCache<boolean>();

export function shouldFoldMfm(source: string, mode: string): boolean {
  if (source.length > MFM_FOLD_LENGTH_THRESHOLD) return true;
  if (mode !== 'all' && mode !== 'sensitive') return false;

  return foldCache(`${mode}\u0000${source}`, () =>
    mode === 'all' ? hasAnyMfmFn(source) : hasSensitiveFoldTags(source),
  );
}

const plainTextCache = createLruCache<string>();
let domParser: DOMParser | null = null;

export function mfmPlainTextFromHtml(html: string): string {
  return plainTextCache(html, () => {
    domParser ??= new DOMParser();
    const doc = domParser.parseFromString(html, 'text/html');
    for (const br of doc.querySelectorAll('br')) br.replaceWith('\n');
    for (const paragraph of doc.querySelectorAll('p')) paragraph.after('\n');
    return doc.body.textContent || '';
  });
}
