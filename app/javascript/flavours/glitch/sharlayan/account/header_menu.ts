import type { useIntl } from 'react-intl';
import { defineMessages } from 'react-intl';

import { refetchAccount } from '@/flavours/glitch/actions/accounts';
import {
  initDomainMuteModal,
  unmuteDomain,
} from '@/flavours/glitch/actions/domain_mutes';
import { apiRequestPost } from '@/flavours/glitch/api';
import {
  avatarDecorationsEnabled,
  showAvatarDecorations,
} from '@/flavours/glitch/initial_state';
import type { Account } from '@/flavours/glitch/models/account';
import type { MenuItem } from '@/flavours/glitch/models/dropdown_menu';
import type { Relationship } from '@/flavours/glitch/models/relationship';
import type { AppDispatch } from '@/flavours/glitch/store';
import RefreshIcon from '@/material-icons/400-24px/refresh.svg?react';
import VolumeOffIcon from '@/material-icons/400-24px/volume_off.svg?react';

const messages = defineMessages({
  domainMute: {
    id: 'account.menu.mute_domain',
    defaultMessage: 'Mute {domain}',
  },
  domainUnmute: {
    id: 'account.menu.unmute_domain',
    defaultMessage: 'Unmute {domain}',
  },
  muteDecorations: {
    id: 'account.menu.mute_decorations',
    defaultMessage: "Hide {name}'s decorations",
  },
  adminBlockDecorations: {
    id: 'account.menu.admin_block_decorations',
    defaultMessage: "Hide {name}'s decorations for everyone",
  },
  adminBlockDomainDecorations: {
    id: 'account.menu.admin_block_domain_decorations',
    defaultMessage: 'Block decorations from {domain}',
  },
  refetchProfile: {
    id: 'account.menu.refetch_profile',
    defaultMessage: 'Refresh profile data',
  },
  muteReactions: {
    id: 'account.menu.mute_reactions',
    defaultMessage: "Don't receive reactions from {name}",
  },
  muteDomainReactions: {
    id: 'account.menu.mute_domain_reactions',
    defaultMessage: "Don't receive reactions from {domain}",
  },
});

interface SharlayanMenuContext {
  account: Account;
  relationship?: Relationship;
  dispatch: AppDispatch;
  intl: ReturnType<typeof useIntl>;
  signedIn: boolean;
  isRemote: boolean;
  remoteDomain: string | null | undefined;
}

export function sharlayanRefetchProfileItems({
  account,
  dispatch,
  intl,
  signedIn,
  isRemote,
}: SharlayanMenuContext): MenuItem[] {
  if (!isRemote || !signedIn) {
    return [];
  }

  return [
    {
      text: intl.formatMessage(messages.refetchProfile),
      action: () => {
        dispatch(refetchAccount(account.id));
      },
      icon: RefreshIcon,
    },
  ];
}

export function sharlayanDomainMuteItems({
  account,
  relationship,
  dispatch,
  intl,
  remoteDomain,
}: SharlayanMenuContext): MenuItem[] {
  if (!remoteDomain) {
    return [];
  }

  return [
    {
      text: intl.formatMessage(
        relationship?.domain_muting
          ? messages.domainUnmute
          : messages.domainMute,
        { domain: remoteDomain },
      ),
      action: () => {
        if (relationship?.domain_muting) {
          dispatch(unmuteDomain(remoteDomain));
        } else {
          dispatch(initDomainMuteModal(account));
        }
      },
      dangerous: true,
      icon: VolumeOffIcon,
      iconId: 'domain-mute',
    },
  ];
}

export function sharlayanReactionMuteItems({
  account,
  intl,
  remoteDomain,
}: SharlayanMenuContext): MenuItem[] {
  const items: MenuItem[] = [];

  if (
    avatarDecorationsEnabled &&
    showAvatarDecorations &&
    account.avatar_decorations.length > 0
  ) {
    items.push(null, {
      text: intl.formatMessage(messages.muteDecorations, {
        name: account.username,
      }),
      action: () => {
        void apiRequestPost('v1/avatar_decoration_mutes', {
          account_id: account.id,
        });
      },
    });
  }

  items.push(null, {
    text: intl.formatMessage(messages.muteReactions, {
      name: account.username,
    }),
    action: () => {
      void apiRequestPost('v1/reaction_mutes', {
        account_id: account.id,
      });
    },
  });

  if (remoteDomain && !account.invalid_handle) {
    items.push({
      text: intl.formatMessage(messages.muteDomainReactions, {
        domain: remoteDomain,
      }),
      action: () => {
        void apiRequestPost('v1/reaction_mutes', {
          domain: remoteDomain,
        });
      },
    });
  }

  return items;
}

export function sharlayanAdminAccountDecorationItems({
  account,
  intl,
}: SharlayanMenuContext): MenuItem[] {
  if (!avatarDecorationsEnabled || account.avatar_decorations.length === 0) {
    return [];
  }

  return [
    {
      text: intl.formatMessage(messages.adminBlockDecorations, {
        name: account.username,
      }),
      href: `/admin/accounts/${account.id}?block_decorations=1`,
      dangerous: true,
    },
  ];
}

export function sharlayanAdminDomainDecorationItems({
  intl,
  remoteDomain,
}: SharlayanMenuContext): MenuItem[] {
  if (!avatarDecorationsEnabled || !remoteDomain) {
    return [];
  }

  return [
    {
      text: intl.formatMessage(messages.adminBlockDomainDecorations, {
        domain: remoteDomain,
      }),
      href: `/admin/avatar_decoration_domain_blocks`,
      dangerous: true,
    },
  ];
}
