import { useCallback, useEffect, useId, useRef, useState } from 'react';

import { FormattedMessage } from 'react-intl';

import { TextInputField } from 'flavours/glitch/components/form_fields';
import { ConfirmationModal } from 'flavours/glitch/features/ui/components/confirmation_modals';

const DriveNameModal: React.FC<{
  title: React.ReactNode;
  label: React.ReactNode;
  confirm: React.ReactNode;
  hint?: React.ReactNode;
  maxLength: number;
  initialName?: string;
  onSubmit: (name: string) => void;
  onClose: () => void;
}> = ({
  title,
  label,
  confirm,
  hint,
  maxLength,
  initialName,
  onSubmit,
  onClose,
}) => {
  const inputId = useId();
  const inputRef = useRef<HTMLInputElement>(null);
  const [name, setName] = useState(initialName ?? '');

  const trimmed = name.trim();

  useEffect(() => {
    inputRef.current?.select();
  }, []);

  const handleChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    setName(e.target.value);
  }, []);

  const handleConfirm = useCallback(() => {
    if (trimmed) onSubmit(trimmed);
  }, [onSubmit, trimmed]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLInputElement>) => {
      if (e.key !== 'Enter' || !trimmed) return;

      e.preventDefault();
      onSubmit(trimmed);
      onClose();
    },
    [onSubmit, onClose, trimmed],
  );

  return (
    <ConfirmationModal
      title={title}
      onClose={onClose}
      onConfirm={handleConfirm}
      disabled={!trimmed || trimmed === initialName}
      confirm={confirm}
      noFocusButton
    >
      <TextInputField
        ref={inputRef}
        id={inputId}
        label={label}
        value={name}
        onChange={handleChange}
        onKeyDown={handleKeyDown}
        maxLength={maxLength}
      />

      {hint && <p className='drive__name-hint'>{hint}</p>}
    </ConfirmationModal>
  );
};

export const DriveFolderNameModal: React.FC<{
  initialName?: string;
  onSubmit: (name: string) => void;
  onClose: () => void;
}> = ({ initialName, onSubmit, onClose }) => (
  <DriveNameModal
    title={
      initialName ? (
        <FormattedMessage
          id='drive.rename_folder'
          defaultMessage='Rename folder'
        />
      ) : (
        <FormattedMessage id='drive.new_folder' defaultMessage='New folder' />
      )
    }
    label={
      <FormattedMessage
        id='drive.new_folder_prompt'
        defaultMessage='Folder name'
      />
    }
    confirm={
      initialName ? (
        <FormattedMessage id='drive.rename' defaultMessage='Rename' />
      ) : (
        <FormattedMessage id='drive.create' defaultMessage='Create' />
      )
    }
    maxLength={60}
    initialName={initialName}
    onSubmit={onSubmit}
    onClose={onClose}
  />
);

export const DriveFileNameModal: React.FC<{
  initialName?: string;
  fileName?: string | null;
  onSubmit: (name: string) => void;
  onClose: () => void;
}> = ({ initialName, fileName, onSubmit, onClose }) => (
  <DriveNameModal
    title={
      <FormattedMessage id='drive.rename_file' defaultMessage='Rename file' />
    }
    label={
      <FormattedMessage
        id='drive.rename_file_prompt'
        defaultMessage='Display name'
      />
    }
    confirm={<FormattedMessage id='drive.rename' defaultMessage='Rename' />}
    hint={
      fileName ? (
        <FormattedMessage
          id='drive.rename_file_hint'
          defaultMessage='Only the name shown in your drive changes. The uploaded file stays {fileName}.'
          values={{ fileName: <strong>{fileName}</strong> }}
        />
      ) : undefined
    }
    maxLength={128}
    initialName={initialName}
    onSubmit={onSubmit}
    onClose={onClose}
  />
);
