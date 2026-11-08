// Run from the repository root with `node .../navigation_seam.mjs`.
// Pixel 1 (dpr 2.625) draws the mobile navigation bar 54.5px tall against the 55px the composer stands on; the
// messages behind showed through that half pixel as a thin line (android-masto-final3, observation 1).
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import process from 'node:process';
import { pathToFileURL } from 'node:url';

const resolve = createRequire(path.resolve('package.json')).resolve;
const { chromium, webkit } = (
  await import(pathToFileURL(resolve('playwright')).href)
).default;
const css = process.env.CHAT_TEST_CSS
  ? fs.readFileSync(process.env.CHAT_TEST_CSS, 'utf8')
  : (await import(pathToFileURL(resolve('sass')).href)).default.compile(
      'app/javascript/flavours/glitch/styles/mastodon/custom_chat.scss',
    ).css;
const html = `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{margin:0;font:16px sans-serif;--mobile-bottom-nav-height:55px;--color-bg-primary:#fff;--color-border-primary:#fff;background:#fff}${css}.behind{height:40px;margin:0;background:#f00}.ui__navigation-bar{position:fixed;bottom:0;height:54.5px;width:100%;background:#fff;box-sizing:border-box}</style>
<div class="chat-native" style="min-height:2400px"><div class="chat-native__messages" style="min-height:2200px">${'<p class="behind"></p>'.repeat(60)}</div><form class="chat-native__composer"><textarea>draft</textarea><button>send</button></form><div class="chat-native__end"></div></div><div class="ui__navigation-bar"></div>`;
const engines = (process.env.CHAT_CHECK_ENGINES ?? 'chromium,webkit').split(
  ',',
);
let failed = false;
for (const [name, engine] of [
  ['chromium', chromium],
  ['webkit', webkit],
].filter(([name]) => engines.includes(name))) {
  const browser = await engine.launch({
    headless: true,
    args:
      name === 'chromium' ? ['--no-sandbox', '--disable-dev-shm-usage'] : [],
  });
  try {
    const context = await browser.newContext({
      viewport: { width: 411, height: 603 },
      deviceScaleFactor: 2.625,
      isMobile: name === 'chromium',
      hasTouch: true,
    });
    const page = await context.newPage();
    await page.setContent(html);
    await page.evaluate(() => window.scrollTo(0, 800));
    const geometry = await page.evaluate(() => {
      const composer = document
        .querySelector('.chat-native__composer')
        .getBoundingClientRect();
      const navigation = document
        .querySelector('.ui__navigation-bar')
        .getBoundingClientRect();
      return { composerBottom: composer.bottom, navigationTop: navigation.top };
    });
    // The rows of device pixels from just above the composer's bottom to just below the bar's top.
    const top = Math.floor(geometry.composerBottom) - 2;
    const shot = await page.screenshot({
      clip: { x: 0, y: top, width: 411, height: 6 },
    });
    const { PNG } = await import(pathToFileURL(resolve('pngjs')).href);
    const image = PNG.sync.read(shot);
    let red = 0;
    for (let i = 0; i < image.data.length; i += 4) {
      const [r, g, b] = image.data.subarray(i, i + 3);
      if (r > 200 && g < 200 && b < 200) red += 1;
    }
    process.stdout.write(
      `${name} ${JSON.stringify({ ...geometry, redPixels: red })}\n`,
    );
    assert.ok(
      geometry.navigationTop > geometry.composerBottom,
      `${name}: the bar must leave the half pixel this check is about`,
    );
    assert.equal(red, 0, `${name}: messages show between composer and bar`);
  } catch (error) {
    failed = true;
    console.error(name, error.message);
  } finally {
    await browser.close();
  }
}
if (failed) process.exitCode = 1;
