#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { GLYPHS } from './birdsiteui-glyphs.mjs';

const root = path.resolve(fileURLToPath(new URL('../..', import.meta.url)));
const assets = path.join(root, 'node_modules/@phosphor-icons/core/assets');
const outFile = path.join(
  root,
  'app/javascript/flavours/glitch/styles/birdsiteui/variables/_icons-phosphor.scss',
);

const version = JSON.parse(
  fs.readFileSync(
    path.join(root, 'node_modules/@phosphor-icons/core/package.json'),
    'utf8',
  ),
).version;

function normalize(svg) {
  return svg
    .replace(/\s*<!--[\s\S]*?-->\s*/g, '')
    .replace(/fill="currentColor"/g, 'fill="#000"')
    .replace(/stroke="currentColor"/g, 'stroke="#000"')
    .replace(/\s+/g, ' ')
    .trim();
}

function encode(svg) {
  return svg
    .replace(/"/g, "'")
    .replace(/%/g, '%25')
    .replace(/#/g, '%23')
    .replace(/</g, '%3C')
    .replace(/>/g, '%3E')
    .replace(/\{/g, '%7B')
    .replace(/\}/g, '%7D');
}

function read(weight, name) {
  const file =
    weight === 'fill'
      ? path.join(assets, 'fill', `${name}-fill.svg`)
      : path.join(assets, 'bold', `${name}-bold.svg`);

  if (!fs.existsSync(file)) {
    throw new Error(
      `Phosphor 자산을 찾을 수 없습니다: ${path.relative(root, file)}`,
    );
  }

  return encode(normalize(fs.readFileSync(file, 'utf8')));
}

const lines = [
  '// 이 파일은 생성된 결과물입니다. 직접 편집하지 마세요.',
  `// 출처: @phosphor-icons/core ${version} (MIT)`,
  '// 재생성: node util/icons/generate-birdsiteui-icons.mjs',
  '// stylelint-disable plugin/no-unused-custom-properties',
  '',
  ':root {',
];

for (const [key, name] of Object.entries(GLYPHS)) {
  lines.push(
    `  --icon-${key}: url("data:image/svg+xml,${read('regular', name)}");`,
  );
  lines.push(
    `  --icon-${key}-fill: url("data:image/svg+xml,${read('fill', name)}");`,
  );
}

lines.push('}', '');

fs.writeFileSync(outFile, lines.join('\n'));

const bytes = fs.statSync(outFile).size;
console.log(
  `${path.relative(root, outFile)}: 글리프 ${Object.keys(GLYPHS).length}개 / 변수 ${
    Object.keys(GLYPHS).length * 2
  }개 / ${(bytes / 1024).toFixed(1)}KB`,
);
