import { useCallback, useMemo } from 'react';

import type { List } from 'immutable';

import { EmojiHTML } from '@/flavours/glitch/components/emoji/html';
import { MfmRenderer } from '@/flavours/glitch/components/mfm';
import { useElementHandledLink } from '@/flavours/glitch/components/status/handled_link';
import { mfmAnimations, mfmEnabled } from '@/flavours/glitch/initial_state';
import type { CustomEmoji } from '@/flavours/glitch/models/custom_emoji';
import type { Status } from '@/flavours/glitch/models/status';

import type { Mention } from './embedded_status';

const mfmDomParser = new DOMParser();
function extractPlainTextFromHtml(html: string): string {
  const doc = mfmDomParser.parseFromString(html, 'text/html');
  for (const br of doc.querySelectorAll('br')) br.replaceWith('\n');
  for (const p of doc.querySelectorAll('p')) p.after('\n');
  return doc.body.textContent || '';
}

export const EmbeddedStatusContent: React.FC<{
  status: Status;
  className?: string;
}> = ({ status, className }) => {
  const mentions = useMemo(
    () => (status.get('mentions') as List<Mention>).toJS(),
    [status],
  );
  const hrefToMention = useCallback(
    (href: string) => {
      return mentions.find((item) => item.url === href);
    },
    [mentions],
  );
  const htmlHandlers = useElementHandledLink({
    hashtagAccountId: status.get('account') as string | undefined,
    hrefToMention,
  });

  const isMfm = (status.get('mfm') as boolean) && mfmEnabled;

  if (isMfm) {
    const storedMfmText = status.get('mfm_text') as string | null;
    const contentHtml = status.get('contentHtml') as string;
    const mfmText = storedMfmText ?? extractPlainTextFromHtml(contentHtml);
    return (
      <div className={className} lang={status.get('language') as string}>
        <MfmRenderer
          text={mfmText}
          emojis={status.get('emojis') as List<CustomEmoji>}
          animationsEnabled={mfmAnimations}
        />
      </div>
    );
  }

  return (
    <EmojiHTML
      {...htmlHandlers}
      className={className}
      lang={status.get('language') as string}
      htmlString={status.get('contentHtml') as string}
      extraEmojis={status.get('emojis') as List<CustomEmoji>}
    />
  );
};
