import { createRoot } from 'react-dom/client';

import { Provider } from 'react-redux';

import { fetchFavoriteEmojis } from '@/flavours/glitch-classic/actions/favorite_emojis';
import { fetchServer } from '@/flavours/glitch-classic/actions/server';
import { hydrateStore } from '@/flavours/glitch-classic/actions/store';
import { Router } from '@/flavours/glitch-classic/components/router';
import { initializeEmoji } from '@/flavours/glitch-classic/features/emoji';
import { Compose } from '@/flavours/glitch-classic/features/standalone/compose';
import { initialState } from '@/flavours/glitch-classic/initial_state';
import { IntlProvider } from '@/flavours/glitch-classic/locales';
import { loadPolyfills } from '@/flavours/glitch-classic/polyfills';
import ready from '@/flavours/glitch-classic/ready';
import { store } from '@/flavours/glitch-classic/store';

async function loaded() {
  const mountNode = document.getElementById('mastodon-compose');

  if (!mountNode) {
    return;
  }

  if (initialState) {
    store.dispatch(hydrateStore(initialState));
  }

  if (initialState?.meta.me) {
    store.dispatch(fetchFavoriteEmojis());
  }

  await store.dispatch(fetchServer());
  await initializeEmoji();

  const root = createRoot(mountNode);

  root.render(
    <IntlProvider>
      <Provider store={store}>
        <Router>
          <Compose />
        </Router>
      </Provider>
    </IntlProvider>,
  );
}

function main() {
  ready(loaded).catch((error: unknown) => {
    console.error(error);
  });
}

loadPolyfills()
  .then(main)
  .catch((error: unknown) => {
    console.error(error);
  });
