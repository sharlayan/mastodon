import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import process from 'node:process';
import { pathToFileURL } from 'node:url';

const resolve = createRequire(path.resolve('package.json')).resolve;
const { chromium, webkit, devices } = (
  await import(pathToFileURL(resolve('playwright')).href)
).default;
const css = process.env.CHAT_TEST_CSS
  ? fs.readFileSync(process.env.CHAT_TEST_CSS, 'utf8')
  : (await import(pathToFileURL(resolve('sass')).href)).default.compile(
      'app/javascript/flavours/glitch/styles/mastodon/custom_chat.scss',
    ).css;
const html = `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{margin:0;font:16px sans-serif;--mobile-bottom-nav-height:55px}${css}.ui__navigation-bar{position:fixed;bottom:80px;height:55px;width:100%}</style>
<div class="chat-native" style="min-height:1200px"><div class="chat-native__messages" style="min-height:1000px"><p>Reading older messages</p></div><form class="chat-native__composer" style="--chat-keyboard-lift:80px"><textarea>draft stays visible</textarea><button>send</button></form><div class="chat-native__end"></div></div><div class="ui__navigation-bar">navigation</div>`;
let failed = false;
for (const [name, engine] of [
  ['chromium', chromium],
  ['webkit', webkit],
]) {
  const browser = await engine.launch({
    headless: true,
    args:
      name === 'chromium' ? ['--no-sandbox', '--disable-dev-shm-usage'] : [],
  });
  try {
    const context = await browser.newContext({
      ...devices['iPhone SE'],
      viewport: { width: 375, height: 367 },
    });
    const page = await context.newPage();
    await page.setContent(html);
    await page.evaluate(() => window.scrollTo(0, 200));
    const geometry = await page.evaluate(() => {
      const composer = document
        .querySelector('.chat-native__composer')
        .getBoundingClientRect();
      const navigation = document
        .querySelector('.ui__navigation-bar')
        .getBoundingClientRect();
      return {
        composerBottom: composer.bottom,
        navigationTop: navigation.top,
        navigationBottom: navigation.bottom,
        visibleBottom: innerHeight - 80,
      };
    });
    process.stdout.write(`${name} ${JSON.stringify(geometry)}\n`);
    assert.ok(
      Math.abs(geometry.navigationBottom - geometry.visibleBottom) <= 1,
      `${name}: navigation must be above the obscured area`,
    );
    assert.ok(
      geometry.composerBottom <= geometry.navigationTop + 1,
      `${name}: composer must remain above navigation`,
    );
    assert.ok(
      geometry.composerBottom >= geometry.navigationTop - 1,
      `${name}: composer should stay adjacent to navigation`,
    );
  } catch (error) {
    failed = true;
    console.error(name, error.message);
  } finally {
    await browser.close();
  }
}
if (failed) process.exitCode = 1;
