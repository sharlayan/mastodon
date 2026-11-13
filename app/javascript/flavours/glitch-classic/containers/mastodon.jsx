import { PureComponent } from 'react';

import { Helmet } from '@unhead/react/helmet';
import { Route } from 'react-router-dom';

import { Provider as ReduxProvider } from 'react-redux';

import { fetchFavoriteEmojis } from 'flavours/glitch-classic/actions/favorite_emojis';
import { checkDeprecatedLocalSettings } from 'flavours/glitch-classic/actions/local_settings';
import { hydrateStore } from 'flavours/glitch-classic/actions/store';
import { connectUserStream } from 'flavours/glitch-classic/actions/streaming';
import { BodyScrollLock } from '@/flavours/glitch-classic/hooks/useBodyScrollLock';
import ErrorBoundary from 'flavours/glitch-classic/components/error_boundary';
import { FocusTargetProvider } from '@/flavours/glitch-classic/components/navigation_focus_target';
import { Router } from 'flavours/glitch-classic/components/router';
import UI from 'flavours/glitch-classic/features/ui';
import { LinkedNotificationsPoller } from 'flavours/glitch-classic/sharlayan/account_switcher/linked_notifications_poller';
import { IdentityContext, createIdentityContext } from 'flavours/glitch-classic/identity_context';
import { initialState, title as siteTitle } from 'flavours/glitch-classic/initial_state';
import { IntlProvider } from 'flavours/glitch-classic/locales';
import { store } from 'flavours/glitch-classic/store';
import { isProduction } from 'flavours/glitch-classic/utils/environment';

import { ScrollContext } from './scroll_container/scroll_context';

const title = isProduction() ? siteTitle : `${siteTitle} (Dev)`;

const hydrateAction = hydrateStore(initialState);

store.dispatch(hydrateAction);

// check for deprecated local settings
store.dispatch(checkDeprecatedLocalSettings());

if (initialState.meta.me) {
  store.dispatch(fetchFavoriteEmojis());
}

export default class Mastodon extends PureComponent {
  identity = createIdentityContext(initialState);

  componentDidMount() {
    if (this.identity.signedIn) {
      this.disconnect = store.dispatch(connectUserStream());
    }
  }

  componentWillUnmount () {
    if (this.disconnect) {
      this.disconnect();
      this.disconnect = null;
    }
  }

  render () {
    return (
      <IdentityContext.Provider value={this.identity}>
        <IntlProvider>
          <ReduxProvider store={store}>
            <ErrorBoundary>
              <Router>
                <ScrollContext>
                  <FocusTargetProvider>
                    <Route path='/' component={UI} />
                  </FocusTargetProvider>
                </ScrollContext>
                <BodyScrollLock />
              </Router>

              {this.identity.signedIn && <LinkedNotificationsPoller />}

              <Helmet defaultTitle={title} titleTemplate={`%s - ${title}`} />
            </ErrorBoundary>
          </ReduxProvider>
        </IntlProvider>
      </IdentityContext.Provider>
    );
  }

}
