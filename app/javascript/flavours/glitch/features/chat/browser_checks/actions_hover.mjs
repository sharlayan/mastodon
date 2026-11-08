// Run from the repository root with `node .../actions_hover.mjs`.
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
const html = `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{margin:0;font:16px sans-serif}${css}</style><div class="chat-native"><div class="chat-native__messages"><article class="chat-native__message"><span class="chat-native__avatar-space"></span><div class="chat-native__message-content"><div class="chat-native__bubble-wrap"><div class="chat-native__bubble" tabindex="-1"><button class="chat-native__reply-quote">quote</button><p>Message <a href="#link">link</a></p><button class="chat-native__reaction">reaction</button><button class="attachment">attachment</button></div><div class="chat-native__actions-rail"><div class="chat-native__actions"><button>tool</button></div></div></div></div></article></div><form class="chat-native__composer"><textarea aria-label="compose"></textarea></form></div>`;
// A message near the top of a phone's screen, under the column header held there (Pixel 1 on f496c2c: header bottom
// 50.8, the toolbar held 54px down and 40px tall over the top of the bubble, android-masto-final6 s7f).
const icon =
  '<button class="icon-button"><svg class="icon" viewBox="0 0 24 24"></svg></button>';
const filler = '<p style="height:60px;margin:0"></p>'.repeat(12);
const topHtml = `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{margin:0;font:16px sans-serif;--mobile-bottom-nav-height:55px}${css}.tabs-bar__wrapper{position:sticky;top:0;z-index:2;height:51px;background:#fff}</style><div class="tabs-bar__wrapper"></div><div class="chat-native"><div class="chat-native__messages">${filler}<article class="chat-native__message"><span class="chat-native__avatar-space"></span><div class="chat-native__message-content"><div class="chat-native__bubble-wrap"><div class="chat-native__bubble" tabindex="-1"><button class="chat-native__reply-quote"><strong>Bob</strong><span>The original message</span></button><p>Message <a href="#link">link</a></p><button class="attachment">attachment</button></div><div class="chat-native__actions-rail"><div class="chat-native__actions">${icon.repeat(3)}</div></div></div><div class="chat-native__reactions"><button class="chat-native__reaction">reaction</button></div></div></article>${filler}</div><form class="chat-native__composer"><textarea aria-label="compose"></textarea></form></div>`;
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
      } else {
        // Moving through the room with the keyboard still shows the toolbar of the message being moved through.
        await page.mouse.move(1270, 890);
        await page.locator('.chat-native__bubble').focus();
        await page.keyboard.press('Tab');
        assert.equal(
          await page.evaluate(() =>
            document.activeElement?.classList.contains(
              'chat-native__reply-quote',
            ),
          ),
          true,
        );
        assert.equal(
          await actions.evaluate((el) => getComputedStyle(el).opacity),
          '1',
          `${name}: the keyboard on a quote still reveals tools`,
        );
      }
      await context.close();
    }

    // The first tap on what a message near the top holds goes to it, not to the toolbar its focus would bring up over
    // it (Pixel 6/6, Galaxy 2/2 on f496c2c: the click went to the bubble's wrapper, the quote never went anywhere).
    const phone =
      name === 'chromium'
        ? {
            viewport: { width: 411, height: 603 },
            deviceScaleFactor: 2.625,
            isMobile: true,
            hasTouch: true,
          }
        : { ...devices['iPhone SE'], viewport: { width: 375, height: 547 } };
    for (const selector of [
      '.chat-native__reply-quote',
      'a[href="#link"]',
      '.attachment',
      '.chat-native__reaction',
      '.chat-native__bubble > p',
    ]) {
      const context = await browser.newContext(phone);
      const page = await context.newPage();
      await page.setContent(topHtml);
      const target = page.locator(selector).first();
      const tapY = 89;
      await target.evaluate((el, y) => {
        const rect = el.getBoundingClientRect();
        window.scrollBy(0, rect.top + Math.min(rect.height, 20) / 2 - y);
      }, tapY);
      const at = await target.evaluate((el) => {
        const rect = el.getBoundingClientRect();
        const bubble = document
          .querySelector('.chat-native__bubble')
          .getBoundingClientRect();
        return {
          x: Math.round(rect.left + Math.min(rect.width, 40) / 2),
          top: rect.top,
          bubbleTop: bubble.top,
        };
      });
      await target.evaluate((el) => {
        document.addEventListener(
          'click',
          (event) => {
            document.body.dataset.clickedOn =
              event.target instanceof Element ? event.target.className : '';
          },
          { capture: true, once: true },
        );
        el.addEventListener(
          'click',
          (event) => {
            event.preventDefault();
            el.dataset.clicked = 'yes';
          },
          { once: true },
        );
      });
      await page.touchscreen.tap(at.x, tapY);
      const result = await page.evaluate(() => {
        const actions = document.querySelector('.chat-native__actions');
        const rect = actions.getBoundingClientRect();
        return {
          clickedOn: document.body.dataset.clickedOn ?? null,
          focused: document.activeElement?.className || null,
          toolbar: {
            opacity: getComputedStyle(actions).opacity,
            top: Math.round(rect.top),
            bottom: Math.round(rect.bottom),
          },
        };
      });
      process.stdout.write(
        `${name} top ${selector} ${JSON.stringify({ ...at, ...result })}\n`,
      );
      try {
        if (selector === '.chat-native__bubble > p') {
          assert.equal(
            result.toolbar.opacity,
            '1',
            `${name}: a tap on the bubble near the top still opens its toolbar`,
          );
        } else {
          assert.equal(
            await target.getAttribute('data-clicked'),
            'yes',
            `${name}: ${selector} near the top responds to its first tap`,
          );
        }
      } catch (error) {
        failed = true;
        console.error(name, error.message);
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
