import { defineMessages, useIntl } from 'react-intl';

import escapeTextContentForBrowser from 'escape-html';

import { EmojiHTML } from '@/mastodon/components/emoji/html';
import { useAccount } from '@/mastodon/hooks/useAccount';
import { useRelationship } from '@/mastodon/hooks/useRelationship';

const messages = defineMessages({
  followMessage: {
    id: 'account.follow_message',
    defaultMessage: 'Follow message',
  },
});

export const SharlayanFollowedMessage: React.FC<{
  accountId: string;
  className?: string;
  labelClassName?: string;
}> = ({ accountId, className, labelClassName }) => {
  const intl = useIntl();
  const account = useAccount(accountId);
  const relationship = useRelationship(accountId);

  if (!account?.followed_message || !relationship?.following) {
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
