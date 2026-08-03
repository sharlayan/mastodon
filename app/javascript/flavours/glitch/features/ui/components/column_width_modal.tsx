import { useCallback, useState } from 'react';

import { FormattedMessage } from 'react-intl';

import { changeColumnParams } from 'flavours/glitch/actions/columns';
import { Button } from 'flavours/glitch/components/button';
import { useAppDispatch } from 'flavours/glitch/store';

import {
  MAX_COLUMN_WIDTH,
  MIN_COLUMN_WIDTH,
  normalizeColumnWidth,
} from '../util/column_width_context';

import { DialogModal } from './dialog_modal';

interface Props {
  columnId?: string;
  width: number;
  onSave?: (width: number) => void;
  onClose: () => void;
}

export const ColumnWidthModal: React.FC<Props> = ({
  columnId,
  width,
  onSave,
  onClose,
}) => {
  const dispatch = useAppDispatch();
  const [value, setValue] = useState(String(normalizeColumnWidth(width)));

  const handleChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setValue(event.currentTarget.value);
    },
    [],
  );

  const handleSubmit = useCallback(
    (event: React.SyntheticEvent<HTMLFormElement>) => {
      event.preventDefault();
      const normalizedWidth = normalizeColumnWidth(value);

      if (onSave) {
        onSave(normalizedWidth);
      } else if (columnId) {
        dispatch(changeColumnParams(columnId, ['width'], normalizedWidth));
      }

      onClose();
    },
    [columnId, dispatch, onClose, onSave, value],
  );

  return (
    <DialogModal
      className='column-width-modal'
      title={
        <FormattedMessage
          id='column_width.title'
          defaultMessage='Adjust column width'
        />
      }
      description={
        <FormattedMessage
          id='column_width.description'
          defaultMessage='Choose a width between {min} and {max} pixels.'
          values={{ min: MIN_COLUMN_WIDTH, max: MAX_COLUMN_WIDTH }}
        />
      }
      onClose={onClose}
      noCancelButton
    >
      <form className='column-width-modal__form' onSubmit={handleSubmit}>
        <label htmlFor='column-width-input'>
          <FormattedMessage id='column_width.label' defaultMessage='Width' />
        </label>
        <div className='column-width-modal__input-row'>
          <input
            id='column-width-input'
            type='number'
            min={MIN_COLUMN_WIDTH}
            max={MAX_COLUMN_WIDTH}
            step={10}
            value={value}
            onChange={handleChange}
            required
          />
          <span>px</span>
        </div>
        <div className='column-width-modal__actions'>
          <Button type='button' secondary onClick={onClose}>
            <FormattedMessage
              id='confirmation_modal.cancel'
              defaultMessage='Cancel'
            />
          </Button>
          <Button type='submit'>
            <FormattedMessage id='column_width.save' defaultMessage='Save' />
          </Button>
        </div>
      </form>
    </DialogModal>
  );
};
