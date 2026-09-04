import { useCallback, useEffect, useLayoutEffect } from 'react';

import { useLayout } from '@/flavours/glitch/hooks/useLayout';
import { useAppDispatch, useAppSelector } from '@/flavours/glitch/store';
import {
  changeComposing,
  mountCompose,
  unmountCompose,
} from 'flavours/glitch/actions/compose';
import { useAppHistory } from 'flavours/glitch/components/router';
import ServerBanner from 'flavours/glitch/components/server_banner';
import { Search } from 'flavours/glitch/features/compose/components/search';
import ComposeFormContainer from 'flavours/glitch/features/compose/containers/compose_form_container';
import { LinkFooter } from 'flavours/glitch/features/ui/components/link_footer';
import { useIdentity } from 'flavours/glitch/identity_context';

export const ComposePanel: React.FC = () => {
  const dispatch = useAppDispatch();
  const handleFocus = useCallback(() => {
    dispatch(changeComposing(true));
  }, [dispatch]);
  const { signedIn } = useIdentity();
  const inlineCompose = useAppSelector(
    (state) =>
      state.local_settings.get('inline_compose_timelines', false) as boolean,
  );
  const hideComposer = useAppSelector((state) => {
    const mounted = state.compose.get('mounted');
    if (typeof mounted === 'number') {
      return mounted > 1;
    }
    return false;
  });

  useEffect(() => {
    dispatch(mountCompose());
    return () => {
      dispatch(unmountCompose());
    };
  }, [dispatch]);

  const { singleColumn } = useLayout();
  const hideForm = inlineCompose && singleColumn;

  return (
    <div className='compose-panel' onFocus={handleFocus}>
      <Search singleColumn={singleColumn} />

      {!signedIn && (
        <>
          <ServerBanner />
          <div className='flex-spacer' />
        </>
      )}

      {signedIn && !hideForm && !hideComposer && (
        <ComposeFormContainer singleColumn />
      )}
      {signedIn && !hideForm && hideComposer && (
        <div className='compose-form' />
      )}
      {signedIn && hideForm && (
        <>
          <ServerBanner />
          <div className='flex-spacer' />
        </>
      )}

      <LinkFooter context={singleColumn ? 'default' : 'multi-column'} />
    </div>
  );
};

/**
 * Redirect the user to the standalone compose page when the
 * sidebar composer is hidden due to a change in viewport size
 * while a post is being written.
 */

export const RedirectToMobileComposeIfNeeded: React.FC = () => {
  const history = useAppHistory();

  const shouldRedirect = useAppSelector((state) =>
    state.compose.get('should_redirect_to_compose_page'),
  );

  useLayoutEffect(() => {
    if (shouldRedirect) {
      history.push('/publish', { focusTarget: false });
    }
  }, [history, shouldRedirect]);

  return null;
};
