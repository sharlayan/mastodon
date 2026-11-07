// Run from the repository root with `node .../actions_hover.browser.mjs`.
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
const html = `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{margin:0;font:16px sans-serif}${css}</style><div class="chat-native"><div class="chat-native__messages"><article class="chat-native__message"><span class="chat-native__avatar-space"></span><div class="chat-native__message-content"><div class="chat-native__bubble-wrap"><div class="chat-native__bubble" tabindex="0"><button class="chat-native__reply-quote">quote</button><p>Message <a href="#link">link</a></p><button class="chat-native__reaction">reaction</button><button class="attachment">attachment</button></div><div class="chat-native__actions-rail"><div class="chat-native__actions"><button>tool</button></div></div></div></div></article></div><form class="chat-native__composer"><textarea aria-label="compose"></textarea></form></div>`;
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
    for (const mode of ['touch', 'mouse']) {
      const options =
        mode === 'touch'
          ? { ...devices['iPhone SE'], viewport: { width: 375, height: 667 } }
          : { viewport: { width: 1280, height: 900 } };
      const context = await browser.newContext(options);
      const page = await context.newPage();
      await page.setContent(html);
      const actions = page.locator('.chat-native__actions');
      await page.locator('.chat-native__bubble p').hover();
      const hoverOpacity = await actions.evaluate(
        (el) => getComputedStyle(el).opacity,
      );
      process.stdout.write(`${name} ${mode} hoverOpacity ${hoverOpacity}\n`);
      assert.equal(
        hoverOpacity,
        mode === 'touch' ? '0' : '1',
        `${name}: hover must reveal tools only on a fine hover pointer`,
      );
      if (mode === 'touch') {
        await page.locator('.chat-native__bubble').focus();
        assert.equal(
          await actions.evaluate((el) => getComputedStyle(el).opacity),
          '1',
          `${name}: focus still reveals tools`,
        );
        for (const selector of [
          '.chat-native__reply-quote',
          'a[href="#link"]',
          '.chat-native__reaction',
          '.attachment',
        ]) {
          const target = page.locator(selector);
          await page.locator('textarea').focus();
          await target.evaluate((el) => {
            el.addEventListener(
              'click',
              (event) => {
                event.preventDefault();
                el.dataset.clicked = 'yes';
              },
              { once: true },
            );
          });
          await target.tap();
          assert.equal(
            await target.getAttribute('data-clicked'),
            'yes',
            `${name}: ${selector} responds to its first tap`,
          );
        }
      }
      await context.close();
    }
  } catch (error) {
    failed = true;
    console.error(name, error.message);
  } finally {
    await browser.close();
  }
}
if (failed) process.exitCode = 1;
