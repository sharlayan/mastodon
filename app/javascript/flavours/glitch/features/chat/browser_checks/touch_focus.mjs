import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import path from 'node:path';
import process from 'node:process';
import { pathToFileURL } from 'node:url';

const resolve = createRequire(path.resolve('package.json')).resolve;
const { chromium, webkit, devices } = (
  await import(pathToFileURL(resolve('playwright')).href)
).default;
const esbuild = (await import(pathToFileURL(resolve('esbuild')).href)).default;
const sass = (await import(pathToFileURL(resolve('sass')).href)).default;
const hook = path.resolve(
  process.env.CHAT_TEST_TOOLBAR_HOOK ??
    'app/javascript/flavours/glitch/features/chat/use_message_toolbar.ts',
);
const css = sass.compile(
  process.env.CHAT_TEST_SCSS ??
    'app/javascript/flavours/glitch/styles/mastodon/custom_chat.scss',
  {
    loadPaths: [path.resolve('app/javascript/flavours/glitch/styles/mastodon')],
  },
).css;
const app = (
  await esbuild.build({
    stdin: {
      contents: `
import { createRoot } from 'react-dom/client';
import { useLongPressOpensToolbar } from ${JSON.stringify(hook)};
const filler = Array.from({length: 12}, (_, i) => <p key={i} style={{height:60,margin:0}} />);
const App = () => {
  const handlers = useLongPressOpensToolbar();
  return <><div className="tabs-bar__wrapper" /><div className="chat-native"><div className="chat-native__messages" {...handlers}>{filler}<article className="chat-native__message"><span className="chat-native__avatar-space"/><div className="chat-native__message-content"><div className="chat-native__bubble-wrap"><div className="chat-native__bubble" tabIndex={-1}><button className="chat-native__reply-quote" onClick={e => {e.preventDefault(); document.body.dataset.clicked = 'quote';}}><strong>Bob</strong><span>The original message</span></button><p>Message <a href="#link">link</a></p></div><div className="chat-native__actions-rail"><div className="chat-native__actions"><button className="icon-button" onClick={() => {document.body.dataset.action = 'yes';}}>one</button><button className="icon-button">two</button><button className="icon-button">three</button></div></div></div></div></article>{filler}</div><form className="chat-native__composer"><textarea /></form></div></>;
};
createRoot(document.getElementById('root')).render(<App/>);`,
      loader: 'tsx',
      resolveDir: path.resolve('.'),
    },
    bundle: true,
    format: 'iife',
    jsx: 'automatic',
    write: false,
    define: { 'process.env.NODE_ENV': '"production"' },
    logLevel: 'error',
  })
).outputFiles[0].text;
const html = `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{margin:0;font:16px sans-serif;--mobile-bottom-nav-height:55px}${css}.tabs-bar__wrapper{position:sticky;top:0;z-index:2;height:51px;background:#fff}</style><div id="root"></div>`;
let failed = false;
for (const [name, engine] of [
  ['chromium', chromium],
  ['webkit', webkit],
].filter(([n]) =>
  (process.env.CHAT_CHECK_ENGINES ?? 'chromium,webkit').split(',').includes(n),
)) {
  const browser = await engine.launch({
    headless: true,
    args:
      name === 'chromium' ? ['--no-sandbox', '--disable-dev-shm-usage'] : [],
  });
  try {
    const context = await browser.newContext({
      ...devices['iPhone SE'],
      viewport: { width: 375, height: 549 },
    });
    const page = await context.newPage();
    await page.setContent(html);
    await page.addScriptTag({ content: app });
    const quote = page.locator('.chat-native__reply-quote strong');
    await quote.waitFor();
    await quote.evaluate((el) => {
      const r = el.getBoundingClientRect();
      window.scrollBy(0, r.top + Math.min(r.height, 20) / 2 - 63);
    });
    await page.locator('textarea').focus();
    await page.evaluate(() =>
      document.addEventListener('mousedown', (e) => {
        if (
          !e.defaultPrevented &&
          e.target instanceof Element &&
          e.target.closest('.chat-native__reply-quote')
        ) {
          e.preventDefault();
          e.target
            .closest('.chat-native__bubble')
            ?.focus({ preventScroll: true });
        }
      }),
    );
    const r = await quote.boundingBox();
    const x = Math.round(r.x + Math.min(r.width, 40) / 2);
    await page.touchscreen.tap(x, 63);
    const result = await page.evaluate(() => ({
      clicked: document.body.dataset.clicked ?? null,
      active: document.activeElement?.className ?? null,
      toolbar: getComputedStyle(document.querySelector('.chat-native__actions'))
        .opacity,
    }));
    process.stdout.write(
      `${name} ${JSON.stringify({ x, y: 63, ...result })}\n`,
    );
    assert.equal(
      result.clicked,
      'quote',
      `${name}: the first tap reaches the quote`,
    );
    assert.notEqual(
      result.active,
      'chat-native__bubble',
      `${name}: the tap does not focus the bubble`,
    );
    const text = page.locator('.chat-native__bubble > p');
    const textBox = await text.boundingBox();
    await page.touchscreen.tap(textBox.x + 8, textBox.y + textBox.height / 2);
    process.stdout.write(
      `${name} text short ${JSON.stringify(await page.evaluate(() => ({ active: document.activeElement?.className, opacity: getComputedStyle(document.querySelector('.chat-native__actions')).opacity })))}\n`,
    );
    assert.equal(
      await page
        .locator('.chat-native__actions')
        .evaluate((el) => getComputedStyle(el).opacity),
      '1',
      `${name}: a short tap on text opens the toolbar`,
    );
    await page.evaluate(() => document.activeElement?.blur());
    await text.evaluate((el) => {
      const event = new Event('touchstart', { bubbles: true });
      Object.defineProperty(event, 'touches', {
        value: [{ identifier: 1, target: el, clientX: 100, clientY: 100 }],
      });
      el.dispatchEvent(event);
    });
    await page.waitForTimeout(550);
    assert.equal(
      await page
        .locator('.chat-native__actions')
        .evaluate((el) => getComputedStyle(el).opacity),
      '1',
      `${name}: a long press on text opens the toolbar`,
    );
    await text.evaluate((el) =>
      el.dispatchEvent(new Event('touchend', { bubbles: true })),
    );
    process.stdout.write(
      `${name} text short tap and synthetic long press opened toolbar\n`,
    );
    await page.evaluate(() => document.activeElement?.blur());
    await quote.evaluate((el) => {
      const event = new Event('touchstart', { bubbles: true });
      Object.defineProperty(event, 'touches', {
        value: [{ identifier: 1, target: el, clientX: 119, clientY: 306 }],
      });
      el.dispatchEvent(event);
    });
    await page.waitForTimeout(500);
    await quote.evaluate((el) => el.closest('button').focus());
    await page.waitForTimeout(100);
    await quote.evaluate((el) =>
      el.dispatchEvent(new Event('touchend', { bubbles: true })),
    );
    const afterHold = await page
      .locator('.chat-native__actions')
      .evaluate((el) => getComputedStyle(el).opacity);
    process.stdout.write(
      `${name} quote hold after native-style focus ${afterHold}\n`,
    );
    assert.equal(
      afterHold,
      '1',
      `${name}: the toolbar stays open after the browser focuses a long-pressed quote`,
    );
    await page.locator('.chat-native__actions button').first().tap();
    assert.equal(
      await page.evaluate(() => document.body.dataset.action),
      'yes',
      `${name}: a toolbar button works after the long press`,
    );
    await context.close();
  } catch (error) {
    failed = true;
    console.error(name, error.message);
  } finally {
    await browser.close();
  }
}
if (failed) process.exitCode = 1;
