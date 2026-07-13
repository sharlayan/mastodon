import { useMemo } from 'react';

import classNames from 'classnames';

import * as mfm from 'mfm-js';

import { useAppSelector } from '../../store';
import { EmojiHTML } from '../emoji/html';
import { MfmRenderer } from '../mfm';
import { useElementHandledLink } from '../status/handled_link';

import classes from './styles.module.scss';

const mfmDomParser = new DOMParser();

interface AccountBioProps {
  className?: string;
  accountId: string;
  showDropdown?: boolean;
}

export const AccountBio: React.FC<AccountBioProps> = ({
  className = classes.bio,
  accountId,
  showDropdown = false,
}) => {
  const htmlHandlers = useElementHandledLink({
    hashtagAccountId: showDropdown ? accountId : undefined,
  });

  const note = useAppSelector((state) => {
    const account = state.accounts.get(accountId);
    if (!account) {
      return '';
    }
    return account.note_emojified;
  });
  const extraEmojis = useAppSelector((state) => {
    const account = state.accounts.get(accountId);
    return account?.emojis;
  });
  const mfmEnabled = useAppSelector(
    (state) => state.accounts.get(accountId)?.mfm ?? false,
  );

  const plainText = useMemo(() => {
    if (!note) return '';
    const doc = mfmDomParser.parseFromString(note, 'text/html');
    return doc.body.textContent || '';
  }, [note]);

  const hasMfm = useMemo(() => {
    if (!mfmEnabled) return false;
    if (!plainText) return false;
    try {
      const ast = mfm.parse(plainText);
      return mfm.extract(ast, (node) => node.type === 'fn').length > 0;
    } catch {
      return false;
    }
  }, [plainText, mfmEnabled]);

  if (note.length === 0) {
    return null;
  }

  if (hasMfm) {
    return (
      <div className={classNames(className, 'translate')}>
        <MfmRenderer text={plainText} emojis={extraEmojis} isProfile />
      </div>
    );
  }

  return (
    <EmojiHTML
      htmlString={note}
      extraEmojis={extraEmojis}
      className={classNames(className, 'translate')}
      {...htmlHandlers}
    />
  );
};
