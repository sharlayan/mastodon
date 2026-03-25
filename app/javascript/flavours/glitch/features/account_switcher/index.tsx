import { useCallback, useEffect, useState } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';

import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import NotificationsIcon from '@/material-icons/400-24px/notifications.svg?react';
import PersonAddIcon from '@/material-icons/400-24px/person_add.svg?react';
import PersonRemoveIcon from '@/material-icons/400-24px/person_remove.svg?react';
import CheckIcon from '@/material-icons/400-24px/person_shield.svg?react';
import {
  fetchAccountSwitches,
  deleteAccountSwitch,
  enableLinkedPushForward,
  disableLinkedPushForward,
} from 'flavours/glitch/actions/account_switches';
import { Avatar } from 'flavours/glitch/components/avatar';
import { DisplayName } from 'flavours/glitch/components/display_name';
import { Icon } from 'flavours/glitch/components/icon';
import { IconButton } from 'flavours/glitch/components/icon_button';
import { me } from 'flavours/glitch/initial_state';
import { useAppSelector, useAppDispatch } from 'flavours/glitch/store';

const messages = defineMessages({
  title: {
    id: 'account_switcher.title',
    defaultMessage: 'Switch account',
  },
  addAccount: {
    id: 'account_switcher.add_account',
    defaultMessage: 'Add account',
  },
  removeAccount: {
    id: 'account_switcher.remove_account',
    defaultMessage: 'Remove account',
  },
  currentAccount: {
    id: 'account_switcher.current_account',
    defaultMessage: 'Current account',
  },
  parentAccount: {
    id: 'account_switcher.parent_account',
    defaultMessage: 'Main account',
  },
  backTo: {
    id: 'account_switcher.back_to',
    defaultMessage: 'Back to {name}',
  },
  switchTo: {
    id: 'account_switcher.switch_to',
    defaultMessage: 'Switch to {name}',
  },
  close: {
    id: 'account_switcher.close',
    defaultMessage: 'Close',
  },
  switchAccountConfirm: {
    id: 'account_switcher.switch_account_confirm',
    defaultMessage: 'Switch to {name}?',
  },
  removeAccountConfirm: {
    id: 'account_switcher.remove_account_confirm',
    defaultMessage: 'Are you sure you want to unlink {name} (@{acct})?',
  },
  notifications: {
    id: 'account_switcher.notifications',
    defaultMessage: 'Notifications',
  },
  receiveNotifications: {
    id: 'account_switcher.receive_notifications',
    defaultMessage: 'Receive in-app notifications',
  },
  receivePushNotifications: {
    id: 'account_switcher.receive_push_notifications',
    defaultMessage: 'Receive push notifications',
  },
  notifHint: {
    id: 'account_switcher.notif_hint',
    defaultMessage:
      'Receive notifications for this account while using another account',
  },
});

export interface LinkedNotifPrefs {
  inApp: boolean;
  push: boolean;
}

const PREFS_KEY = (meId: string) => `linked_notif_prefs_${meId}`;

export const getLinkedNotifPrefs = (
  meId: string,
): Record<string, LinkedNotifPrefs> => {
  try {
    return JSON.parse(localStorage.getItem(PREFS_KEY(meId)) ?? '{}') as Record<
      string,
      LinkedNotifPrefs
    >;
  } catch {
    return {};
  }
};

export const setLinkedNotifPref = (
  meId: string,
  accountId: string,
  prefs: LinkedNotifPrefs,
) => {
  const prevAll = getLinkedNotifPrefs(meId);
  const wasInApp = prevAll[accountId]?.inApp ?? false;

  const all = { ...prevAll };
  all[accountId] = prefs;
  localStorage.setItem(PREFS_KEY(meId), JSON.stringify(all));

  if (prefs.inApp && !wasInApp) {
    const lastIdKey = `linked_notif_last_id_${meId}_${accountId}`;
    if (!localStorage.getItem(lastIdKey)) {
      const nowSnowflake = (BigInt(Date.now()) << 16n).toString();
      localStorage.setItem(lastIdKey, nowSnowflake);
    }
  }
};

const OAUTH_POPUP_WIDTH = 600;
const OAUTH_POPUP_HEIGHT = 700;
const OAUTH_TIMEOUT = 120000;

const openOAuthPopup = (url: string): Window | null => {
  const left = window.screenX + (window.innerWidth - OAUTH_POPUP_WIDTH) / 2;
  const top = window.screenY + (window.innerHeight - OAUTH_POPUP_HEIGHT) / 2;

  return window.open(
    url,
    'multi_account_auth',
    `width=${OAUTH_POPUP_WIDTH},height=${OAUTH_POPUP_HEIGHT},left=${left},top=${top},popup=yes`,
  );
};

interface AccountSwitcherModalProps {
  onClose: () => void;
}

export const AccountSwitcherModal: React.FC<AccountSwitcherModalProps> = ({
  onClose,
}) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const [addingAccount, setAddingAccount] = useState(false);

  const items = useAppSelector((state) => state.accountSwitches.get('items'));
  const parentAccountId = useAppSelector(
    (state) => state.accountSwitches.get('parentAccountId') as string | null,
  );
  const isLoading = useAppSelector(
    (state) => state.accountSwitches.get('isLoading') as boolean,
  );
  const loaded = useAppSelector(
    (state) => state.accountSwitches.get('loaded') as boolean,
  );

  useEffect(() => {
    if (!loaded) {
      void dispatch(fetchAccountSwitches());
    }
  }, [dispatch, loaded]);

  const handleAddAccount = useCallback(async () => {
    if (addingAccount) return;
    setAddingAccount(true);

    try {
      const response = await fetch('/multi_accounts/entry', {
        headers: {
          Accept: 'application/json',
          'X-CSRF-Token':
            document.querySelector<HTMLMetaElement>('meta[name=csrf-token]')
              ?.content ?? '',
        },
      });

      if (!response.ok) throw new Error('Failed to fetch authorization entry');

      const data = (await response.json()) as {
        authorize_url: string;
        state: string;
        nonce: string;
      };

      const popup = openOAuthPopup(data.authorize_url);
      if (!popup) {
        setAddingAccount(false);
        return;
      }

      let messageReceived = false;
      let bc: BroadcastChannel | undefined;

      const handleMessage = (event: MessageEvent) => {
        if (event.origin !== window.location.origin) return;

        const messageData = event.data as {
          type?: string;
          state?: string;
          success?: boolean;
        };

        if (messageData.type !== 'multi_account_callback') return;
        if (messageData.state !== data.state) return;

        messageReceived = true;
        window.removeEventListener('message', handleMessage);
        if (bc) {
          bc.close();
          bc = undefined;
        }

        if (messageData.success) {
          void dispatch(fetchAccountSwitches()).then(() => {
            setAddingAccount(false);
          });
        } else {
          setAddingAccount(false);
        }
      };

      window.addEventListener('message', handleMessage);

      if (typeof BroadcastChannel !== 'undefined') {
        bc = new BroadcastChannel('multi_account_auth');
        bc.onmessage = (event: MessageEvent) => {
          const syntheticEvent = Object.assign(
            Object.create(Object.getPrototypeOf(event) as object),
            event,
            { origin: window.location.origin },
          ) as MessageEvent;
          handleMessage(syntheticEvent);
        };
      }

      const cleanup = () => {
        window.removeEventListener('message', handleMessage);
        if (bc) {
          bc.close();
          bc = undefined;
        }
      };

      setTimeout(() => {
        if (!messageReceived) {
          cleanup();
          setAddingAccount(false);
        }
      }, OAUTH_TIMEOUT);

      const checkPopup = setInterval(() => {
        if (popup.closed) {
          clearInterval(checkPopup);
          setTimeout(() => {
            if (!messageReceived) {
              cleanup();
              setAddingAccount(false);
            }
          }, 1000);
        }
      }, 500);
    } catch {
      setAddingAccount(false);
    }
  }, [addingAccount, dispatch]);

  const handleRemoveAccount = useCallback(
    (id: string, name: string, acct: string) => {
      if (
        window.confirm(
          intl.formatMessage(messages.removeAccountConfirm, { name, acct }),
        )
      ) {
        void dispatch(deleteAccountSwitch({ id }));
      }
    },
    [dispatch, intl],
  );

  const handleSwitchAccount = useCallback(
    (_accountId: string, name: string) => {
      if (
        window.confirm(
          intl.formatMessage(messages.switchAccountConfirm, { name }),
        )
      ) {
        window.location.href = `/auth/sign_in?switch_to=${_accountId}`;
      }
    },
    [intl],
  );

  const authList = items as unknown as
    | {
        toArray(): {
          id: string;
          target_account_id: string;
          created_at: string;
        }[];
      }
    | undefined;

  const handleAddAccountClick = useCallback(() => {
    void handleAddAccount();
  }, [handleAddAccount]);

  return (
    <div className='modal-root__modal account-switcher-modal'>
      <div className='account-switcher-modal__header'>
        <h3>{intl.formatMessage(messages.title)}</h3>
        <IconButton
          icon=''
          iconComponent={CloseIcon}
          onClick={onClose}
          title={intl.formatMessage(messages.close)}
        />
      </div>

      <div className='account-switcher-modal__content'>
        {parentAccountId && (
          <ParentAccountItem
            accountId={parentAccountId}
            onSwitch={handleSwitchAccount}
          />
        )}

        {me && <CurrentAccountItem isMain={parentAccountId === null} />}

        {isLoading && !loaded && (
          <div className='account-switcher-modal__loading'>
            <div className='loading-indicator__figure' />
          </div>
        )}

        {authList?.toArray().map((auth) => (
          <SwitchableAccountItem
            key={auth.id}
            authId={auth.id}
            accountId={auth.target_account_id}
            onSwitch={handleSwitchAccount}
            onRemove={handleRemoveAccount}
          />
        ))}
      </div>

      <div className='account-switcher-modal__footer'>
        <button
          className='account-switcher-modal__add-button'
          onClick={handleAddAccountClick}
          disabled={addingAccount}
          type='button'
        >
          <Icon id='person-add' icon={PersonAddIcon} />
          <span>
            {addingAccount ? '...' : intl.formatMessage(messages.addAccount)}
          </span>
        </button>
      </div>
    </div>
  );
};

const ParentAccountItem: React.FC<{
  accountId: string;
  onSwitch: (accountId: string, name: string) => void;
}> = ({ accountId, onSwitch }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const account = useAppSelector((state) => state.accounts.get(accountId));

  const accountData = account as unknown as
    | { get(key: string): string }
    | undefined;
  const displayName =
    accountData?.get('display_name') ??
    accountData?.get('username') ??
    accountId;

  const [showNotifSettings, setShowNotifSettings] = useState(false);
  const [inAppEnabled, setInAppEnabled] = useState(() => {
    if (!me) return false;
    return getLinkedNotifPrefs(me)[accountId]?.inApp ?? false;
  });
  const [pushEnabled, setPushEnabled] = useState(() => {
    if (!me) return false;
    return getLinkedNotifPrefs(me)[accountId]?.push ?? false;
  });

  const handleSwitch = useCallback(() => {
    onSwitch(accountId, displayName);
  }, [accountId, displayName, onSwitch]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === 'Enter' || e.key === ' ') handleSwitch();
    },
    [handleSwitch],
  );

  const handleToggleNotifSettings = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
    setShowNotifSettings((v) => !v);
  }, []);

  const handleNotifPanelClick = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
  }, []);

  const handleNotifPanelKeyDown = useCallback((e: React.KeyboardEvent) => {
    e.stopPropagation();
  }, []);

  const handleInAppChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      e.stopPropagation();
      if (!me) return;
      const checked = e.target.checked;
      setInAppEnabled(checked);
      const current = getLinkedNotifPrefs(me)[accountId] ?? {
        inApp: false,
        push: false,
      };
      setLinkedNotifPref(me, accountId, { ...current, inApp: checked });
    },
    [accountId],
  );

  const handlePushChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      e.stopPropagation();
      if (!me) return;
      const checked = e.target.checked;
      setPushEnabled(checked);
      const current = getLinkedNotifPrefs(me)[accountId] ?? {
        inApp: false,
        push: false,
      };
      setLinkedNotifPref(me, accountId, { ...current, push: checked });

      if (checked) {
        void dispatch(enableLinkedPushForward({ linkedAccountId: accountId }));
      } else {
        void dispatch(disableLinkedPushForward({ linkedAccountId: accountId }));
      }
    },
    [accountId, dispatch],
  );

  if (!account) return null;

  return (
    <div
      className={classNames(
        'account-switcher-modal__item',
        'account-switcher-modal__item--parent',
        { 'account-switcher-modal__item--notif-open': showNotifSettings },
      )}
    >
      <div
        className='account-switcher-modal__item__row'
        onClick={handleSwitch}
        onKeyDown={handleKeyDown}
        role='button'
        tabIndex={0}
        title={intl.formatMessage(messages.backTo, { name: displayName })}
      >
        <div className='account-switcher-modal__item__avatar'>
          <Avatar account={account as never} size={36} />
        </div>
        <div className='account-switcher-modal__item__info'>
          <span className='account-switcher-modal__parent-label'>
            {intl.formatMessage(messages.parentAccount)}
          </span>
          <DisplayName account={account as never} />
        </div>
        <div className='account-switcher-modal__item__actions'>
          <button
            className={classNames('account-switcher-modal__notif-button', {
              active: inAppEnabled || pushEnabled,
              open: showNotifSettings,
            })}
            onClick={handleToggleNotifSettings}
            type='button'
            title={intl.formatMessage(messages.notifications)}
            aria-expanded={showNotifSettings}
          >
            <Icon id='notifications' icon={NotificationsIcon} />
          </button>
          <span
            className='account-switcher-modal__check-button'
            title={intl.formatMessage(messages.parentAccount)}
          >
            <Icon id='check' icon={CheckIcon} />
          </span>
        </div>
      </div>

      {showNotifSettings && (
        /* eslint-disable-next-line jsx-a11y/no-static-element-interactions -- event propagation boundary only */
        <div
          onClick={handleNotifPanelClick}
          onKeyDown={handleNotifPanelKeyDown}
        >
          <div
            className='account-switcher-modal__notif-settings'
            role='group'
            aria-label={intl.formatMessage(messages.notifications)}
          >
            <label className='account-switcher-modal__notif-label'>
              <input
                type='checkbox'
                checked={inAppEnabled}
                onChange={handleInAppChange}
              />
              <span>{intl.formatMessage(messages.receiveNotifications)}</span>
            </label>
            <label className='account-switcher-modal__notif-label'>
              <input
                type='checkbox'
                checked={pushEnabled}
                onChange={handlePushChange}
              />
              <span>
                {intl.formatMessage(messages.receivePushNotifications)}
              </span>
            </label>
          </div>
        </div>
      )}
    </div>
  );
};

const CurrentAccountItem: React.FC<{ isMain: boolean }> = ({ isMain }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const account = useAppSelector((state) =>
    me ? state.accounts.get(me) : undefined,
  );

  const [showNotifSettings, setShowNotifSettings] = useState(false);
  const [inAppEnabled, setInAppEnabled] = useState(() => {
    if (!me) return false;
    return getLinkedNotifPrefs(me)[me]?.inApp ?? false;
  });
  const [pushEnabled, setPushEnabled] = useState(() => {
    if (!me) return false;
    return getLinkedNotifPrefs(me)[me]?.push ?? false;
  });

  const handleToggleNotifSettings = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
    setShowNotifSettings((v) => !v);
  }, []);

  const handleNotifPanelClick = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
  }, []);

  const handleNotifPanelKeyDown = useCallback((e: React.KeyboardEvent) => {
    e.stopPropagation();
  }, []);

  const handleInAppChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      e.stopPropagation();
      if (!me) return;
      const checked = e.target.checked;
      setInAppEnabled(checked);
      const current = getLinkedNotifPrefs(me)[me] ?? {
        inApp: false,
        push: false,
      };
      setLinkedNotifPref(me, me, { ...current, inApp: checked });
    },
    [],
  );

  const handlePushChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      e.stopPropagation();
      if (!me) return;
      const checked = e.target.checked;
      setPushEnabled(checked);
      const current = getLinkedNotifPrefs(me)[me] ?? {
        inApp: false,
        push: false,
      };
      setLinkedNotifPref(me, me, { ...current, push: checked });

      if (checked) {
        void dispatch(enableLinkedPushForward({ linkedAccountId: me }));
      } else {
        void dispatch(disableLinkedPushForward({ linkedAccountId: me }));
      }
    },
    [dispatch],
  );

  if (!account) return null;

  return (
    <div
      className={classNames(
        'account-switcher-modal__item',
        'account-switcher-modal__item--current',
        { 'account-switcher-modal__item--notif-open': showNotifSettings },
      )}
    >
      <div className='account-switcher-modal__item__row'>
        <div className='account-switcher-modal__item__avatar'>
          <Avatar account={account as never} size={36} />
        </div>
        <div className='account-switcher-modal__item__info'>
          <span className='account-switcher-modal__parent-label'>
            {intl.formatMessage(
              isMain ? messages.parentAccount : messages.currentAccount,
            )}
          </span>
          <DisplayName account={account as never} />
        </div>
        <div className='account-switcher-modal__item__actions'>
          <button
            className={classNames('account-switcher-modal__notif-button', {
              active: inAppEnabled || pushEnabled,
              open: showNotifSettings,
            })}
            onClick={handleToggleNotifSettings}
            type='button'
            title={intl.formatMessage(messages.notifications)}
            aria-expanded={showNotifSettings}
          >
            <Icon id='notifications' icon={NotificationsIcon} />
          </button>
          {isMain && (
            <span
              className='account-switcher-modal__check-button'
              title={intl.formatMessage(messages.currentAccount)}
            >
              <Icon id='check' icon={CheckIcon} />
            </span>
          )}
        </div>
      </div>

      {showNotifSettings && (
        /* eslint-disable-next-line jsx-a11y/no-static-element-interactions -- event propagation boundary only */
        <div
          onClick={handleNotifPanelClick}
          onKeyDown={handleNotifPanelKeyDown}
        >
          <div
            className='account-switcher-modal__notif-settings'
            role='group'
            aria-label={intl.formatMessage(messages.notifications)}
          >
            <span className='account-switcher-modal__notif-hint'>
              {intl.formatMessage(messages.notifHint)}
            </span>
            <label className='account-switcher-modal__notif-label'>
              <input
                type='checkbox'
                checked={inAppEnabled}
                onChange={handleInAppChange}
              />
              <span>{intl.formatMessage(messages.receiveNotifications)}</span>
            </label>
            <label className='account-switcher-modal__notif-label'>
              <input
                type='checkbox'
                checked={pushEnabled}
                onChange={handlePushChange}
              />
              <span>
                {intl.formatMessage(messages.receivePushNotifications)}
              </span>
            </label>
          </div>
        </div>
      )}
    </div>
  );
};

const SwitchableAccountItem: React.FC<{
  authId: string;
  accountId: string;
  onSwitch: (accountId: string, name: string) => void;
  onRemove: (authId: string, name: string, acct: string) => void;
}> = ({ authId, accountId, onSwitch, onRemove }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const account = useAppSelector((state) => state.accounts.get(accountId));

  const accountData = account as unknown as
    | { get(key: string): string }
    | undefined;
  const displayName =
    accountData?.get('display_name') ??
    accountData?.get('username') ??
    accountId;
  const acctHandle =
    accountData?.get('acct') ?? accountData?.get('username') ?? accountId;

  const [showNotifSettings, setShowNotifSettings] = useState(false);
  const [inAppEnabled, setInAppEnabled] = useState(() => {
    if (!me) return false;
    return getLinkedNotifPrefs(me)[accountId]?.inApp ?? false;
  });
  const [pushEnabled, setPushEnabled] = useState(() => {
    if (!me) return false;
    return getLinkedNotifPrefs(me)[accountId]?.push ?? false;
  });

  const handleToggleNotifSettings = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
    setShowNotifSettings((v) => !v);
  }, []);

  const handleNotifPanelClick = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
  }, []);

  const handleNotifPanelKeyDown = useCallback((e: React.KeyboardEvent) => {
    e.stopPropagation();
  }, []);

  const handleInAppChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      e.stopPropagation();
      if (!me) return;
      const checked = e.target.checked;
      setInAppEnabled(checked);
      const current = getLinkedNotifPrefs(me)[accountId] ?? {
        inApp: false,
        push: false,
      };
      setLinkedNotifPref(me, accountId, { ...current, inApp: checked });
    },
    [accountId],
  );

  const handlePushChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      e.stopPropagation();
      if (!me) return;
      const checked = e.target.checked;
      setPushEnabled(checked);
      const current = getLinkedNotifPrefs(me)[accountId] ?? {
        inApp: false,
        push: false,
      };
      setLinkedNotifPref(me, accountId, { ...current, push: checked });

      if (checked) {
        void dispatch(enableLinkedPushForward({ linkedAccountId: accountId }));
      } else {
        void dispatch(disableLinkedPushForward({ linkedAccountId: accountId }));
      }
    },
    [accountId, dispatch],
  );

  const handleSwitch = useCallback(() => {
    onSwitch(accountId, displayName);
  }, [accountId, displayName, onSwitch]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === 'Enter' || e.key === ' ') handleSwitch();
    },
    [handleSwitch],
  );

  const handleRemove = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      onRemove(authId, displayName, acctHandle);
    },
    [authId, displayName, acctHandle, onRemove],
  );

  if (!account) return null;

  return (
    <div
      className={classNames(
        'account-switcher-modal__item',
        'account-switcher-modal__item--switchable',
        { 'account-switcher-modal__item--notif-open': showNotifSettings },
      )}
    >
      <div
        className='account-switcher-modal__item__row'
        onClick={handleSwitch}
        onKeyDown={handleKeyDown}
        role='button'
        tabIndex={0}
        title={intl.formatMessage(messages.switchTo, { name: displayName })}
      >
        <div className='account-switcher-modal__item__avatar'>
          <Avatar account={account as never} size={36} />
        </div>
        <div className='account-switcher-modal__item__info'>
          <DisplayName account={account as never} />
        </div>
        <div className='account-switcher-modal__item__actions'>
          <button
            className={classNames('account-switcher-modal__notif-button', {
              active: inAppEnabled || pushEnabled,
              open: showNotifSettings,
            })}
            onClick={handleToggleNotifSettings}
            type='button'
            title={intl.formatMessage(messages.notifications)}
            aria-expanded={showNotifSettings}
          >
            <Icon id='notifications' icon={NotificationsIcon} />
          </button>

          <button
            className='account-switcher-modal__remove-button'
            onClick={handleRemove}
            type='button'
            title={intl.formatMessage(messages.removeAccount)}
          >
            <Icon id='person-remove' icon={PersonRemoveIcon} />
          </button>
        </div>
      </div>

      {showNotifSettings && (
        /* eslint-disable-next-line jsx-a11y/no-static-element-interactions -- event propagation boundary only */
        <div
          onClick={handleNotifPanelClick}
          onKeyDown={handleNotifPanelKeyDown}
        >
          <div
            className='account-switcher-modal__notif-settings'
            role='group'
            aria-label={intl.formatMessage(messages.notifications)}
          >
            <label className='account-switcher-modal__notif-label'>
              <input
                type='checkbox'
                checked={inAppEnabled}
                onChange={handleInAppChange}
              />
              <span>{intl.formatMessage(messages.receiveNotifications)}</span>
            </label>
            <label className='account-switcher-modal__notif-label'>
              <input
                type='checkbox'
                checked={pushEnabled}
                onChange={handlePushChange}
              />
              <span>
                {intl.formatMessage(messages.receivePushNotifications)}
              </span>
            </label>
          </div>
        </div>
      )}
    </div>
  );
};
