// Run from the repository root with `node .../bubble_layout.mjs`.
// This uses real layout engines because jsdom does not implement flex sizing.
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
const long = '긴문장'.repeat(100);
const html = `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{margin:0;font:16px sans-serif}${css}</style>
<div class="chat-native"><div class="chat-native__messages">
<article class="chat-native__message"><a class="account__avatar" style="width:36px;height:36px"></a><div class="chat-native__message-content"><strong>test</strong><div class="chat-native__bubble-wrap"><div class="chat-native__bubble"><button class="chat-native__reply-quote"><strong>test</strong><span>이전 메시지</span></button><p>인용 메시지</p></div></div></div></article>
<article class="chat-native__message chat-native__message--continued" id="short"><span class="chat-native__avatar-space"></span><div class="chat-native__message-content"><div class="chat-native__bubble-wrap"><div class="chat-native__bubble"><p>확인 24778</p></div></div><div class="chat-native__message-footer"><time>13:12</time></div></div></article>
<article class="chat-native__message chat-native__message--continued" id="long"><span class="chat-native__avatar-space"></span><div class="chat-native__message-content"><div class="chat-native__bubble-wrap"><div class="chat-native__bubble"><p>${long}</p></div></div></div></article>
<article class="chat-native__message chat-native__message--mine" id="mine"><div class="chat-native__message-content"><div class="chat-native__bubble-wrap"><div class="chat-native__bubble"><p>${long}</p></div></div></div></article>
</div></div>`;
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
      viewport: { width: 375, height: 667 },
    });
    const page = await context.newPage();
    await page.setContent(html);
    const geometry = await page.evaluate(() => {
      const short = document.querySelector('#short p');
      const node = short.firstChild;
      const rows = new Set();
      for (let i = 0; i < node.length; i++) {
        const range = document.createRange();
        range.setStart(node, i);
        range.setEnd(node, i + 1);
        rows.add(Math.round(range.getBoundingClientRect().top));
      }
      const box = (selector) => {
        const b = document.querySelector(selector).getBoundingClientRect();
        return { left: b.left, right: b.right, width: b.width };
      };
      return {
        shortLines: rows.size,
        avatar: box('#short .chat-native__avatar-space'),
        short: box('#short p'),
        long: box('#long .chat-native__bubble'),
        mine: box('#mine .chat-native__bubble'),
        viewport: innerWidth,
      };
    });
    process.stdout.write(`${name} ${JSON.stringify(geometry)}\n`);
    assert.equal(
      geometry.shortLines,
      1,
      `${name}: a short continued message must fit on one line`,
    );
    assert.ok(
      geometry.avatar.width >= 35,
      `${name}: a continued message must retain the avatar column`,
    );
    for (const key of ['long', 'mine']) {
      assert.ok(
        geometry[key].left >= -1 &&
          geometry[key].right <= geometry.viewport + 1,
        `${name}: ${key} must wrap inside the viewport`,
      );
    }
    await page.addStyleTag({ content: '.chat-native { width: 280px; }' });
    const narrow = await page.evaluate(() => {
      const container = document
        .querySelector('.chat-native')
        .getBoundingClientRect();
      return ['#long .chat-native__bubble', '#mine .chat-native__bubble'].map(
        (selector) => {
          const bubble = document
            .querySelector(selector)
            .getBoundingClientRect();
          return {
            left: bubble.left - container.left,
            right: bubble.right - container.left,
            width: container.width,
          };
        },
      );
    });
    for (const bubble of narrow) {
      assert.ok(
        bubble.left >= -1 && bubble.right <= bubble.width + 1,
        `${name}: a narrow column must contain the bubble`,
      );
    }
  } catch (error) {
    failed = true;
    console.error(name, error.message);
  } finally {
    await browser.close();
  }
}
if (failed) process.exitCode = 1;
