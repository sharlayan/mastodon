import { Provider } from 'react-redux';

import { fetchCustomEmojis } from 'mastodon/actions/custom_emojis';
import { fetchFavoriteEmojis } from 'mastodon/actions/favorite_emojis';
import { fetchServer } from 'mastodon/actions/server';
import { hydrateStore } from 'mastodon/actions/store';
import { Router } from 'mastodon/components/router';
import Compose from 'mastodon/features/standalone/compose';
import { initialState } from 'mastodon/initial_state';
import { IntlProvider } from 'mastodon/locales';
import { store } from 'mastodon/store';

if (initialState) {
  store.dispatch(hydrateStore(initialState));
}

if (initialState && initialState.meta && initialState.meta.me) {
  store.dispatch(fetchCustomEmojis());
  store.dispatch(fetchFavoriteEmojis());
}
store.dispatch(fetchServer());

const ComposeContainer = () => (
  <IntlProvider>
    <Provider store={store}>
      <Router>
        <Compose />
      </Router>
    </Provider>
  </IntlProvider>
);

export default ComposeContainer;
