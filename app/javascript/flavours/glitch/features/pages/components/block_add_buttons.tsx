import { useCallback } from 'react';

import { useIntl } from 'react-intl';

import type { ApiPageBlockType } from 'flavours/glitch/api_types/pages';

import { addBlockMessages } from './block_messages';

export const BlockAddButtons: React.FC<{
  types: ApiPageBlockType[];
  onAdd: (type: ApiPageBlockType) => void;
}> = ({ types, onAdd }) => {
  const intl = useIntl();

  const handleClick = useCallback(
    (event: React.MouseEvent<HTMLButtonElement>) => {
      const type = event.currentTarget.dataset.blockType as ApiPageBlockType;
      onAdd(type);
    },
    [onAdd],
  );

  return (
    <div className='page-editor__add-buttons'>
      {types.map((type) => (
        <button
          key={type}
          type='button'
          className='button button-secondary'
          data-block-type={type}
          onClick={handleClick}
        >
          {intl.formatMessage(addBlockMessages[type])}
        </button>
      ))}
    </div>
  );
};
