import { apiSubmitAccountNote } from 'flavours/glitch-classic/api/accounts';
import { createDataLoadingThunk } from 'flavours/glitch-classic/store/typed_functions';

export const submitAccountNote = createDataLoadingThunk(
  'account_note/submit',
  ({ accountId, note }: { accountId: string; note: string }) =>
    apiSubmitAccountNote(accountId, note),
  (relationship) => ({ relationship }),
);
