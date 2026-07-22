import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const glitchLocaleDirectory = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  '../app/javascript/flavours/glitch/locales',
);
const commonSharlayanDirectory = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  '../app/javascript/mastodon/locales/sharlayan',
);
const glitchSharlayanDirectory = path.join(glitchLocaleDirectory, 'sharlayan');
const locales = ['en', 'ko', 'ja'];
const manifestKeysByDirectory = new Map();

for (const sharlayanDirectory of [
  commonSharlayanDirectory,
  glitchSharlayanDirectory,
]) {
  const manifest = JSON.parse(
    fs.readFileSync(path.join(sharlayanDirectory, 'manifest.json'), 'utf8'),
  );
  const expectedKeys = [...manifest].sort();
  manifestKeysByDirectory.set(sharlayanDirectory, expectedKeys);

  for (const locale of locales) {
    const fragment = JSON.parse(
      fs.readFileSync(path.join(sharlayanDirectory, `${locale}.json`), 'utf8'),
    );
    const fragmentKeys = Object.keys(fragment).sort();

    if (JSON.stringify(fragmentKeys) !== JSON.stringify(expectedKeys)) {
      throw new Error(
        `${locale} Sharlayan locale keys do not match ${path.relative(glitchLocaleDirectory, sharlayanDirectory)}/manifest.json`,
      );
    }
  }
}

const commonKeys = manifestKeysByDirectory.get(commonSharlayanDirectory);
const glitchKeys = manifestKeysByDirectory.get(glitchSharlayanDirectory);

if (!commonKeys || !glitchKeys) {
  throw new Error('Could not load Sharlayan locale manifests');
}

const duplicatedKeys = commonKeys.filter((key) => glitchKeys.includes(key));

if (duplicatedKeys.length > 0) {
  throw new Error(
    `Common and glitch Sharlayan locale manifests overlap: ${duplicatedKeys.join(', ')}`,
  );
}

for (const locale of locales) {
  for (const localeDirectory of [
    path.join(glitchLocaleDirectory, '../../../mastodon/locales'),
    glitchLocaleDirectory,
  ]) {
    const generatedLocale = JSON.parse(
      fs.readFileSync(path.join(localeDirectory, `${locale}.json`), 'utf8'),
    );
    const leakedKeys = commonKeys.filter((key) =>
      Object.hasOwn(generatedLocale, key),
    );

    if (leakedKeys.length > 0) {
      throw new Error(
        `${locale} common Sharlayan locale keys leaked into ${path.relative(glitchLocaleDirectory, localeDirectory)}: ${leakedKeys.join(', ')}`,
      );
    }
  }
}
