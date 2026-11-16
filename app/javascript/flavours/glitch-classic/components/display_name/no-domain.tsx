import type { ComponentPropsWithoutRef, FC } from 'react';
import { useState } from 'react';

import classNames from 'classnames';

import { AnimateEmojiProvider } from '../emoji/context';
import { EmojiHTML } from '../emoji/html';
import { EmojiInfoTooltip } from '../emoji_info_tooltip';
import { Skeleton } from '../skeleton';

import type { DisplayNameProps } from './index';

export const DisplayNameWithoutDomain: FC<
  Omit<DisplayNameProps, 'variant'> & ComponentPropsWithoutRef<'span'>
> = ({
  account,
  className,
  children,
  disableEmojiTooltip,
  localDomain: _,
  ...props
}) => {
  const [containerElement, setContainerElement] = useState<HTMLElement | null>(
    null,
  );

  return (
    <AnimateEmojiProvider
      {...props}
      as='span'
      className={classNames('display-name', className)}
    >
      <bdi ref={setContainerElement}>
        {account ? (
          <EmojiHTML
            className='display-name__html'
            htmlString={account.display_name_html}
            as='strong'
            extraEmojis={account.emojis}
          />
        ) : (
          <strong className='display-name__html'>
            <Skeleton width='10ch' />
          </strong>
        )}
        <EmojiInfoTooltip
          containerRef={{ current: containerElement }}
          enabled={!disableEmojiTooltip}
        />
      </bdi>
      {children}
    </AnimateEmojiProvider>
  );
};
