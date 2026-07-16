import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const localeDirectory = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  '../app/javascript/flavours/glitch/locales',
);
const sharlayanDirectory = path.join(localeDirectory, 'sharlayan');
const locales = ['en', 'ko', 'ja'];
const manifest = JSON.parse(
  fs.readFileSync(path.join(sharlayanDirectory, 'manifest.json'), 'utf8'),
);
const expectedKeys = [...manifest].sort();

for (const locale of locales) {
  const fragment = JSON.parse(
    fs.readFileSync(path.join(sharlayanDirectory, `${locale}.json`), 'utf8'),
  );
  const fragmentKeys = Object.keys(fragment).sort();

  if (JSON.stringify(fragmentKeys) !== JSON.stringify(expectedKeys)) {
    throw new Error(
      `${locale} Sharlayan locale keys do not match the manifest`,
    );
  }
}
