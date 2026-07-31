import { useCallback, useState } from 'react';

import { useIntl } from 'react-intl';

import type { ApiPageBlockType } from 'flavours/glitch/api_types/pages';

import { addBlockMessages } from './block_messages';

export const BlockAddButtons: React.FC<{
  types: ApiPageBlockType[];
  onAdd: (type: ApiPageBlockType) => void;
}> = ({ types, onAdd }) => {
  const intl = useIntl();
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);

  const addBlockLabel = intl.formatMessage({
    id: 'pages.add_block',
    defaultMessage: 'Add block',
  });

  const handleClick = useCallback(
    (event: React.MouseEvent<HTMLButtonElement>) => {
      const type = event.currentTarget.dataset.blockType as ApiPageBlockType;
      onAdd(type);
    },
    [onAdd],
  );

  const handleMobileMenuToggle = useCallback(
    (event: React.MouseEvent<HTMLButtonElement>) => {
      const blockAdder = event.currentTarget.parentElement;
      const willOpen = event.currentTarget.ariaExpanded !== 'true';

      setIsMobileMenuOpen(willOpen);

      if (willOpen && window.matchMedia('(width < 480px)').matches) {
        requestAnimationFrame(() => {
          blockAdder?.scrollIntoView({ behavior: 'smooth', block: 'end' });
        });
      }
    },
    [],
  );

  const buttons = () =>
    types.map((type) => (
      <button
        key={type}
        type='button'
        className='button button-secondary'
        data-block-type={type}
        onClick={handleClick}
      >
        {intl.formatMessage(addBlockMessages[type])}
      </button>
    ));

  return (
    <div className='page-editor__block-adder'>
      <div className='page-editor__add-buttons page-editor__add-buttons--inline'>
        {buttons()}
      </div>

      <div className='page-editor__block-adder__mobile'>
        <button
          type='button'
          className='button button-secondary'
          aria-expanded={isMobileMenuOpen}
          onClick={handleMobileMenuToggle}
        >
          {addBlockLabel}
        </button>

        {isMobileMenuOpen && (
          <div className='page-editor__add-buttons'>{buttons()}</div>
        )}
      </div>
    </div>
  );
};
