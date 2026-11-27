import { useCallback } from 'react';

import { FormattedMessage } from 'react-intl';

import { useHistory } from 'react-router';

import { openModal } from '@/flavours/glitch/actions/modal';
import { MenuItem, MenuItemDivider } from '@/flavours/glitch/components/menu';
import { useColumnWidthContext } from '@/flavours/glitch/features/ui/util/column_width_context';
import { useAppDispatch } from '@/flavours/glitch/store';

interface MultiColumnMenuItemsProps {
  withDivider?: boolean;
  pinned: boolean;
  onPin: () => void;
  onMove?: (direction: number) => void;
}

export const MultiColumnMenuItems: React.FC<MultiColumnMenuItemsProps> = ({
  withDivider = false,
  onPin,
  onMove,
  pinned,
}) => {
  const history = useHistory();
  const dispatch = useAppDispatch();
  const { columnId, width, onSave } = useColumnWidthContext();
  const canAdjustWidth = Boolean(width && (columnId ?? onSave));

  const adjustWidth = useCallback(() => {
    dispatch(
      openModal({
        modalType: 'COLUMN_WIDTH',
        modalProps: { columnId, width, onSave },
      }),
    );
  }, [columnId, dispatch, onSave, width]);

  const togglePin = useCallback(() => {
    if (!pinned) {
      history.replace('/');
    }

    onPin();
  }, [history, pinned, onPin]);

  const moveLeft = useCallback(() => {
    onMove?.(-1);
  }, [onMove]);

  const moveRight = useCallback(() => {
    onMove?.(1);
  }, [onMove]);

  return (
    <>
      {withDivider && <MenuItemDivider />}
      <MenuItem onClick={togglePin} keepMenuOpenOnClick>
        {pinned ? (
          <FormattedMessage
            id='column_header.unpin_column'
            defaultMessage='Unpin column'
          />
        ) : (
          <FormattedMessage
            id='column_header.pin_column'
            defaultMessage='Pin column'
          />
        )}
      </MenuItem>
      {canAdjustWidth && (
        <MenuItem onClick={adjustWidth}>
          <FormattedMessage
            id='column_header.adjust_width'
            defaultMessage='Adjust width'
          />
        </MenuItem>
      )}
      {pinned && onMove && (
        <>
          <MenuItem onClick={moveLeft} keepMenuOpenOnClick>
            <FormattedMessage
              id='column_header.move_column_left'
              defaultMessage='Move column left'
            />
          </MenuItem>
          <MenuItem onClick={moveRight} keepMenuOpenOnClick>
            <FormattedMessage
              id='column_header.move_column_right'
              defaultMessage='Move column right'
            />
          </MenuItem>
        </>
      )}
    </>
  );
};
