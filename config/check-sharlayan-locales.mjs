import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const configDirectory = path.dirname(fileURLToPath(import.meta.url));
const glitchLocaleDirectory = path.join(
  configDirectory,
  '../app/javascript/flavours/glitch/locales',
);
const glitchClassicLocaleDirectory = path.join(
  configDirectory,
  '../app/javascript/flavours/glitch-classic/locales',
);
const commonSharlayanDirectory = path.join(
  configDirectory,
  '../app/javascript/mastodon/locales/sharlayan',
);
const flavourLocaleDirectories = [
  glitchLocaleDirectory,
  glitchClassicLocaleDirectory,
];
const locales = ['en', 'ko', 'ja'];
const manifestKeysByDirectory = new Map();

for (const sharlayanDirectory of [
  commonSharlayanDirectory,
  ...flavourLocaleDirectories.map((directory) =>
    path.join(directory, 'sharlayan'),
  ),
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

if (!commonKeys) {
  throw new Error('Could not load Sharlayan locale manifests');
}

for (const flavourLocaleDirectory of flavourLocaleDirectories) {
  const flavourKeys = manifestKeysByDirectory.get(
    path.join(flavourLocaleDirectory, 'sharlayan'),
  );

  if (!flavourKeys) {
    throw new Error('Could not load Sharlayan locale manifests');
  }

  const duplicatedKeys = commonKeys.filter((key) => flavourKeys.includes(key));

  if (duplicatedKeys.length > 0) {
    throw new Error(
      `Common and ${path.relative(glitchLocaleDirectory, flavourLocaleDirectory) || 'glitch'} Sharlayan locale manifests overlap: ${duplicatedKeys.join(', ')}`,
    );
  }
}

for (const locale of locales) {
  for (const localeDirectory of [
    path.join(glitchLocaleDirectory, '../../../mastodon/locales'),
    ...flavourLocaleDirectories,
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
