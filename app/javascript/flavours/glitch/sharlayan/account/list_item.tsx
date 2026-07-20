import { defineMessages, useIntl } from 'react-intl';

import escapeTextContentForBrowser from 'escape-html';

import { EmojiHTML } from '@/flavours/glitch/components/emoji/html';
import type { Account } from '@/flavours/glitch/models/account';
import type { Relationship } from '@/flavours/glitch/models/relationship';
import { useAppSelector } from '@/flavours/glitch/store';

export const SHARLAYAN_FOLLOW_LIST_BIO_CHAR_LIMIT = 100;

export function useSharlayanFollowListBio(): boolean {
  return useAppSelector(
    (state) =>
      // eslint-disable-next-line @typescript-eslint/no-unsafe-call, @typescript-eslint/no-unsafe-member-access
      state.local_settings.getIn(['show_follow_list_bio'], true) as boolean,
  );
}

const messages = defineMessages({
  followMessage: {
    id: 'account.follow_message.short',
    defaultMessage: 'Follow message',
  },
});

export function sharlayanAccountBioHtml(
  account: Account,
  bioCharLimit?: number,
): string {
  if (typeof bioCharLimit !== 'number') {
    return account.note_emojified;
  }

  const plain = account.note_plain ?? '';
  const truncated =
    plain.length > bioCharLimit ? `${plain.slice(0, bioCharLimit)}…` : plain;

  return escapeTextContentForBrowser(truncated);
}

interface FollowedMessageProps {
  account: Account;
  relationship: Relationship | null | undefined;
  className: string | undefined;
  labelClassName: string | undefined;
}

export const SharlayanFollowedMessage: React.FC<FollowedMessageProps> = ({
  account,
  relationship,
  className,
  labelClassName,
}) => {
  const intl = useIntl();

  if (!account.followed_message || !relationship?.following) {
    return null;
  }

  return (
    <div className={className}>
      <span className={labelClassName}>
        {intl.formatMessage(messages.followMessage)}
      </span>
      <EmojiHTML
        as='p'
        htmlString={escapeTextContentForBrowser(account.followed_message)}
        extraEmojis={account.emojis}
      />
    </div>
  );
};
