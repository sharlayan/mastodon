import { useCallback, useId, useState } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';

const messages = defineMessages({
  show: {
    id: 'pages.spoiler.show',
    defaultMessage: 'Show spoiler',
  },
  hide: {
    id: 'pages.spoiler.hide',
    defaultMessage: 'Hide spoiler',
  },
});

export const Spoiler: React.FC<{
  children: React.ReactNode;
  className?: string;
}> = ({ children, className }) => {
  const intl = useIntl();
  const contentId = useId();
  const [revealed, setRevealed] = useState(false);
  const handleToggle = useCallback(() => {
    setRevealed((value) => !value);
  }, []);

  return (
    <div
      className={classNames('page__spoiler', className, {
        'page__spoiler--revealed': revealed,
      })}
    >
      <button
        type='button'
        className='page__spoiler-toggle'
        aria-expanded={revealed}
        aria-controls={contentId}
        onClick={handleToggle}
      >
        {intl.formatMessage(revealed ? messages.hide : messages.show)}
      </button>
      {revealed && (
        <div id={contentId} className='page__spoiler-content'>
          {children}
        </div>
      )}
    </div>
  );
};
