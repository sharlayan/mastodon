import type React from 'react';
import { useCallback } from 'react';

import { quoteComposeCancel } from '@/flavours/glitch-classic/actions/compose_typed';
import { QuotedStatus } from '@/flavours/glitch-classic/components/status/quote';
import { useAppDispatch } from '@/flavours/glitch-classic/store';

export const ComposeQuote: React.FC<{ id: string }> = ({ id }) => {
  const dispatch = useAppDispatch();
  const handleDelete = useCallback(() => {
    dispatch(quoteComposeCancel());
  }, [dispatch]);

  return <QuotedStatus id={id} clamp onDelete={handleDelete} />;
};
