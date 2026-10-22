import { useCallback } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import {
  changeComposeAdvancedOption,
  changeComposeContentType,
} from '@/flavours/glitch/actions/compose';
import {
  MenuItemCheckbox,
  MenuItemDivider,
  MenuItemGroup,
  MenuItemRadio,
} from '@/flavours/glitch/components/menu';
import {
  forceLocalOnly,
  mfmAllowComposition,
} from '@/flavours/glitch/initial_state';
import { changeReactionAcceptance } from '@/flavours/glitch/sharlayan/compose/state';
import { useAppDispatch, useAppSelector } from '@/flavours/glitch/store';

const messages = defineMessages({
  plain: { id: 'compose.content-type.plain', defaultMessage: 'Plain text' },
  markdown: { id: 'compose.content-type.markdown', defaultMessage: 'Markdown' },
  mfm: { id: 'compose.content-type.mfm', defaultMessage: 'MFM' },
  all: { id: 'compose.reaction_acceptance.all', defaultMessage: 'Accept all' },
  likeOnly: {
    id: 'compose.reaction_acceptance.like_only',
    defaultMessage: 'Likes only',
  },
  likeOnlyForRemote: {
    id: 'compose.reaction_acceptance.like_only_remote',
    defaultMessage: 'Remote users: likes only',
  },
  nonSensitiveOnly: {
    id: 'compose.reaction_acceptance.non_sensitive',
    defaultMessage: 'Exclude sensitive emojis',
  },
  nonSensitiveOnlyForLocalLikeOnlyForRemote: {
    id: 'compose.reaction_acceptance.non_sensitive_local_like_remote',
    defaultMessage: 'Exclude sensitive emojis and remote users',
  },
});

const contentTypes = [
  ['text/plain', messages.plain],
  ['text/markdown', messages.markdown],
  ['text/x-mfm', messages.mfm],
] as const;

const reactionOptions = [
  'all',
  'likeOnly',
  'likeOnlyForRemote',
  'nonSensitiveOnly',
  'nonSensitiveOnlyForLocalLikeOnlyForRemote',
] as const;

export const ComposeCustomSettings: React.FC = () => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const showContentType = useAppSelector(
    (state) => !!state.local_settings.get('show_content_type_choice'),
  );
  const contentType = useAppSelector(
    (state) => state.compose.get('content_type') as string,
  );
  const isEditing = useAppSelector((state) => !!state.compose.get('id'));
  const localOnly = useAppSelector(
    (state) => !!state.compose.getIn(['advanced_options', 'do_not_federate']),
  );
  const threaded = useAppSelector(
    (state) => !!state.compose.getIn(['advanced_options', 'threaded_mode']),
  );
  const showReactions = useAppSelector(
    (state) => !!state.local_settings.get('show_reaction_acceptance'),
  );
  const reactionAcceptance = useAppSelector(
    (state) =>
      (state.compose.get('reaction_acceptance') as string | null) ?? 'all',
  );

  const onContentTypeChange = useCallback(
    ({ value }: { value: string }) => {
      dispatch(changeComposeContentType(value));
    },
    [dispatch],
  );
  const onReactionChange = useCallback(
    ({ value }: { value: string }) => {
      dispatch(changeReactionAcceptance(value === 'all' ? null : value));
    },
    [dispatch],
  );
  const onLocalOnlyChange = useCallback(() => {
    dispatch(changeComposeAdvancedOption('do_not_federate', !localOnly));
  }, [dispatch, localOnly]);
  const onThreadedChange = useCallback(() => {
    dispatch(changeComposeAdvancedOption('threaded_mode', !threaded));
  }, [dispatch, threaded]);

  return (
    <>
      {showContentType && (
        <>
          <MenuItemDivider />
          <MenuItemGroup
            label={
              <FormattedMessage
                id='compose.content-type.change'
                defaultMessage='Change advanced formatting options'
              />
            }
          >
            {contentTypes
              .filter(
                ([value]) => value !== 'text/x-mfm' || mfmAllowComposition,
              )
              .map(([value, message]) => (
                <MenuItemRadio
                  key={value}
                  name='content_type'
                  value={value}
                  checked={contentType === value}
                  onChange={onContentTypeChange}
                  keepMenuOpenOnClick
                >
                  {intl.formatMessage(message)}
                </MenuItemRadio>
              ))}
          </MenuItemGroup>
        </>
      )}
      {showReactions && (
        <>
          <MenuItemDivider />
          <MenuItemGroup
            label={
              <FormattedMessage
                id='compose.reaction_acceptance'
                defaultMessage='Reaction acceptance'
              />
            }
          >
            {reactionOptions.map((value) => (
              <MenuItemRadio
                key={value}
                name='reaction_acceptance'
                value={value}
                checked={reactionAcceptance === value}
                onChange={onReactionChange}
                keepMenuOpenOnClick
              >
                {intl.formatMessage(messages[value])}
              </MenuItemRadio>
            ))}
          </MenuItemGroup>
        </>
      )}
      <MenuItemDivider />
      {!forceLocalOnly && (
        <MenuItemCheckbox
          value='local_only'
          checked={localOnly}
          disabled={isEditing}
          onChange={onLocalOnlyChange}
          keepMenuOpenOnClick
          description={
            <FormattedMessage
              id='federation.local_only.long'
              defaultMessage='Prevent this post from reaching other servers'
            />
          }
        >
          <FormattedMessage
            id='federation.local_only.short'
            defaultMessage='Local-only'
          />
        </MenuItemCheckbox>
      )}
      <MenuItemCheckbox
        value='threaded_mode'
        checked={threaded}
        disabled={isEditing}
        onChange={onThreadedChange}
        keepMenuOpenOnClick
      >
        <FormattedMessage
          id='compose.enable_threaded_mode'
          defaultMessage='Enable threaded mode'
        />
      </MenuItemCheckbox>
    </>
  );
};
