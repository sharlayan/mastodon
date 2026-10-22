import { Fragment, useCallback } from 'react';

import { FormattedMessage } from 'react-intl';

import type { Map as ImmutableMap } from 'immutable';

import {
  DotsThreeIcon,
  PaperclipIcon,
  ShareFatIcon,
} from '@phosphor-icons/react';

import { statusInteraction } from '@/flavours/glitch/actions/interactions';
import { openModal } from '@/flavours/glitch/actions/modal';
import { fetchStatus } from '@/flavours/glitch/actions/statuses';
import { selectStatusActionBarOrder } from '@/flavours/glitch/features/status_action_bar/items';
import { useCurrentAccountId } from '@/flavours/glitch/hooks/useAccountId';
import { useAccountStatus } from '@/flavours/glitch/hooks/useStatus';
import { useIdentity } from '@/flavours/glitch/identity_context';
import { clipsEnabled, quickBoosting } from '@/flavours/glitch/initial_state';
import type { AccountStatusShape } from '@/flavours/glitch/models/status';
import { useAppDispatch, useAppSelector } from '@/flavours/glitch/store';

import {
  Button,
  IconButton,
  ToggleButton,
  ToggleIconButton,
} from '../button/redesign';
import {
  Menu,
  MenuItem,
  MenuList,
  MenuTrigger,
  LegacyDropdownMenuItems,
} from '../menu';

import {
  useStatusContext,
  useStatusIcons,
  useStatusMenuActions,
} from './hooks';
import { RemoveQuoteHint } from './legacy/action_bar/remove_quote_hint';
import { StatusReactionPicker } from './reactions';
import classes from './styles.module.scss';

interface StatusActionBarProps {
  statusId: string;
  withDismiss?: boolean;
  withCounters?: boolean;
  /** Only show methods to respond (reply, boost, like) and not sharing, bookmarking, and the overflow menu. */
  onlyResponses?: boolean;
}

export const StatusActionBar: React.FC<StatusActionBarProps> = ({
  statusId,
  withDismiss,
  withCounters,
  onlyResponses,
}) => {
  const status = useAccountStatus(statusId);
  const quotedAccountId = useAppSelector(
    (state) =>
      state.statuses.getIn([status?.quote?.quoted_status, 'account']) ?? null,
  );
  const currentAccountId = useCurrentAccountId();
  const { signedIn } = useIdentity();
  const actionOrder = useAppSelector(selectStatusActionBarOrder) as string[];
  const hiddenActions = useAppSelector(
    (state) =>
      state.local_settings.getIn(['status_action_bar', 'hidden']) as
        | ImmutableMap<string, boolean>
        | undefined,
  );
  const { contextType } = useStatusContext();
  const statusUrl = status?.url ?? status?.uri;

  // Actions
  const dispatch = useAppDispatch();
  const handleClip = useCallback(() => {
    dispatch(openModal({ modalType: 'CLIP_ADD', modalProps: { statusId } }));
  }, [dispatch, statusId]);
  const handleShareClick = useCallback(() => {
    if (!statusUrl) {
      return;
    }

    // We need to make this partial as by default share always is set, despite not being supported in FF.
    const nav = navigator as Partial<Pick<Navigator, 'share'>> &
      Pick<Navigator, 'clipboard'>;
    if (nav.share) {
      void nav.share({
        url: statusUrl,
      });
    } else {
      dispatch(statusInteraction({ statusId, intent: 'copy', contextType }));
    }
  }, [contextType, dispatch, statusId, statusUrl]);

  const { reply, like, bookmark, quote } = useStatusIcons(statusId);
  const quoteExposed = hiddenActions?.get('quote') !== true;

  if (!status) {
    return null;
  }

  const isPublic =
    status.visibility === 'public' || status.visibility === 'unlisted';

  const isQuotingMe = quotedAccountId === currentAccountId;
  const shouldShowQuoteRemovalHint =
    isQuotingMe && contextType === 'notifications';

  const configurableActions: Record<string, React.ReactNode> = {
    favourite: (
      <ToggleButton
        size='sm'
        variant='ghost'
        active={like.active}
        tooltip={{ type: 'label', text: like.title }}
        leadingIcon={like.icon}
        onClick={like.action}
      >
        {withCounters && like.counter}
      </ToggleButton>
    ),
    reaction: <StatusReactionPicker statusId={statusId} />,
    bookmark: !onlyResponses && (
      <ToggleIconButton
        size='sm'
        variant='ghost'
        active={bookmark.active}
        icon={bookmark.icon}
        onClick={bookmark.action}
        disabled={!signedIn}
      >
        {bookmark.title}
      </ToggleIconButton>
    ),
    clip: signedIn && clipsEnabled && (
      <IconButton
        size='sm'
        variant='ghost'
        icon={PaperclipIcon}
        onClick={handleClip}
      >
        <FormattedMessage
          id='status.add_to_clip'
          defaultMessage='Add to clip'
        />
      </IconButton>
    ),
    quote: signedIn && (
      <IconButton
        size='sm'
        variant='ghost'
        icon={quote.icon}
        disabled={quote.disabled}
        onClick={quote.action}
      >
        {quote.title}
      </IconButton>
    ),
  };

  const responseButtons = (
    <>
      <Button
        size='sm'
        clipPadding
        variant='ghost'
        leadingIcon={reply.icon}
        onClick={reply.action}
        disabled={!status.repliable}
        tooltip={{ type: 'label', text: reply.title }}
      >
        {withCounters && reply.counter}
      </Button>

      <StatusReblogButton statusId={statusId} standalone={quoteExposed}>
        {withCounters && status.reblogs_count}
      </StatusReblogButton>

      {actionOrder.map((key) =>
        hiddenActions?.get(key) === true ? null : (
          <Fragment key={key}>{configurableActions[key]}</Fragment>
        ),
      )}
    </>
  );

  if (onlyResponses) {
    return <div className={classes.actions}>{responseButtons}</div>;
  }

  return (
    <div className={classes.actions}>
      {responseButtons}

      <span className={classes.actionsButtonGap} />

      {isPublic && (
        <IconButton
          size='sm'
          variant='ghost'
          icon={ShareFatIcon}
          onClick={handleShareClick}
        >
          <FormattedMessage id='status.share' defaultMessage='Share' />
        </IconButton>
      )}

      <RemoveQuoteHint
        className='status__action-bar__button-wrapper'
        canShowHint={shouldShowQuoteRemovalHint}
      >
        {(dismissQuoteHint) => (
          <StatusActionMenu
            dismissQuoteHint={dismissQuoteHint}
            status={status}
            withDismiss={withDismiss}
          />
        )}
      </RemoveQuoteHint>
    </div>
  );
};

const StatusReblogButton: React.FC<{
  statusId: string;
  standalone?: boolean;
  children: React.ReactNode;
}> = ({ statusId, standalone, children }) => {
  const { boost, quote } = useStatusIcons(statusId);

  if (quickBoosting || standalone) {
    return (
      <ToggleButton
        size='sm'
        variant='ghost'
        active={boost.active}
        tooltip={{
          type: 'label',
          text: boost.title,
        }}
        leadingIcon={boost.icon}
        disabled={boost.disabled}
        onClick={boost.action}
      >
        {children}
      </ToggleButton>
    );
  }

  return (
    <Menu>
      <MenuTrigger
        as={ToggleButton}
        size='sm'
        variant='ghost'
        active={boost.active}
        tooltip={{
          type: 'label',
          text: (
            <FormattedMessage
              id='status.reblog_or_quote'
              defaultMessage='Boost or quote'
            />
          ),
        }}
        leadingIcon={boost.icon}
      >
        {children}
      </MenuTrigger>

      <MenuList placement='bottom' maxWidth={180}>
        <MenuItem
          onClick={boost.action}
          icon={boost.icon}
          disabled={boost.disabled}
          description={boost.meta}
        >
          {boost.title}
        </MenuItem>
        <MenuItem
          onClick={quote.action}
          icon={quote.icon}
          disabled={quote.disabled}
          description={quote.meta}
        >
          {quote.title}
        </MenuItem>
      </MenuList>
    </Menu>
  );
};

const StatusActionMenu: React.FC<{
  dismissQuoteHint: () => void;
  status: AccountStatusShape;
  withDismiss?: boolean;
}> = ({ status, dismissQuoteHint, withDismiss }) => {
  const { contextType } = useStatusContext();
  const dispatch = useAppDispatch();

  const menu = useStatusMenuActions({ status, contextType, withDismiss });

  const onOpen = useCallback(() => {
    // Replicates needsStatusRefresh of the Dropdown component.
    if (quickBoosting && !status.quote_approval) {
      void dispatch(
        fetchStatus(status.id, { forceFetch: true, alsoFetchContext: false }),
      );
    }

    dismissQuoteHint();
  }, [dismissQuoteHint, dispatch, status.id, status.quote_approval]);

  return (
    <Menu onOpen={onOpen}>
      <MenuTrigger
        as={IconButton}
        size='sm'
        variant='ghost'
        icon={DotsThreeIcon}
      >
        <FormattedMessage id='status.more' defaultMessage='More' />
      </MenuTrigger>

      <MenuList placement='top-end'>
        <LegacyDropdownMenuItems items={menu} />
      </MenuList>
    </Menu>
  );
};
