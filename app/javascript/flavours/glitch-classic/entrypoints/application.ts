import { loadLocale } from 'flavours/glitch-classic/locales';
import main from 'flavours/glitch-classic/main';
import { loadPolyfills } from 'flavours/glitch-classic/polyfills';

loadPolyfills()
  .then(loadLocale)
  .then(main)
  .catch((e: unknown) => {
    console.error(e);
  });
