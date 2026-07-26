import { useCallback, useState } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';

import { unicodeHexToUrl } from 'flavours/glitch/features/emoji/normalize';
import { emojiToUnicodeHex } from 'flavours/glitch/features/emoji/utils';
import { autoPlayGif } from 'flavours/glitch/initial_state';
import { assetHost } from 'flavours/glitch/utils/config';

const messages = defineMessages({
  all: { id: 'reactions.all', defaultMessage: 'All' },
  unknownEmoji: { id: 'reactions.unknown_emoji', defaultMessage: 'Unknown' },
});

interface ReactionSummaryEntry {
  name: string;
  count: number;
  url?: string;
  static_url?: string;
  domain?: string;
  is_sensitive?: boolean;
  unknown?: boolean;
}

interface ReactionSummaryBarProps {
  summary: unknown;
  activeFilter: string | null;
  onFilterChange: (name: string | null) => void;
}

export const ReactionSummaryBar: React.FC<ReactionSummaryBarProps> = ({
  summary,
  activeFilter,
  onFilterChange,
}) => {
  const intl = useIntl();

  const handleAllClick = useCallback(() => {
    onFilterChange(null);
  }, [onFilterChange]);

  if (!summary || (summary as ReactionSummaryEntry[]).length === 0) {
    return null;
  }

  const entries = summary as ReactionSummaryEntry[];

  return (
    <div className='reaction-summary-bar'>
      <button
        type='button'
        className={classNames('reaction-summary-bar__item', {
          active: activeFilter === null,
        })}
        onClick={handleAllClick}
      >
        <span className='reaction-summary-bar__item__label'>
          {intl.formatMessage(messages.all)}
        </span>
      </button>

      {entries.map((entry) => (
        <ReactionSummaryItem
          key={`${entry.name}-${entry.domain ?? ''}`}
          entry={entry}
          active={activeFilter === entry.name}
          onFilterChange={onFilterChange}
        />
      ))}
    </div>
  );
};

const ReactionSummaryItem: React.FC<{
  entry: ReactionSummaryEntry;
  active: boolean;
  onFilterChange: (name: string | null) => void;
}> = ({ entry, active, onFilterChange }) => {
  const intl = useIntl();
  const [hovered, setHovered] = useState(false);

  const handleClick = useCallback(() => {
    onFilterChange(active ? null : entry.name);
  }, [active, entry.name, onFilterChange]);

  const handleMouseEnter = useCallback(() => {
    setHovered(true);
  }, []);
  const handleMouseLeave = useCallback(() => {
    setHovered(false);
  }, []);

  const renderEmoji = () => {
    if (entry.unknown) {
      return (
        <span
          className='reaction-summary-bar__item__unknown'
          title={`:${entry.name}:`}
        >
          {intl.formatMessage(messages.unknownEmoji)}
        </span>
      );
    }

    if (!entry.url) {
      const src = unicodeHexToUrl({
        unicodeHex: emojiToUnicodeHex(entry.name),
        assetHost,
      });
      return (
        <img
          draggable={false}
          className='emojione'
          alt={entry.name}
          title={`:${entry.name}:`}
          src={src}
        />
      );
    }

    const src = autoPlayGif || hovered ? entry.url : entry.static_url;
    return (
      <img
        draggable={false}
        className={`emojione custom-emoji${entry.is_sensitive ? ' sensitive-custom-emoji' : ''}`}
        alt={`:${entry.name}:`}
        title={`:${entry.name}:`}
        src={src}
      />
    );
  };

  return (
    <button
      type='button'
      className={classNames('reaction-summary-bar__item', { active })}
      onClick={handleClick}
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
    >
      <span className='reaction-summary-bar__item__emoji'>{renderEmoji()}</span>
      <span className='reaction-summary-bar__item__count'>{entry.count}</span>
    </button>
  );
};
