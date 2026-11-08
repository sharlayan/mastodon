import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import process from 'node:process';
import { pathToFileURL } from 'node:url';

const resolve = createRequire(path.resolve('package.json')).resolve;
const load = async (name) =>
  (await import(pathToFileURL(resolve(name)).href)).default;
const { chromium, webkit } = await load('playwright');
const esbuild = await load('esbuild');
const css = process.env.CHAT_TEST_CSS
  ? fs.readFileSync(process.env.CHAT_TEST_CSS, 'utf8')
  : (await load('sass')).compile(
      'app/javascript/flavours/glitch/styles/mastodon/custom_chat.scss',
    ).css;
const control = (
  await esbuild.build({
    entryPoints: [
      'app/javascript/flavours/glitch/features/chat/scroll_control.ts',
    ],
    bundle: true,
    format: 'iife',
    globalName: 'ScrollControl',
    write: false,
  })
).outputFiles[0].text;

const messages = Array.from(
  { length: 40 },
  (_, index) =>
    `<article class="chat-native__message" id="chat-message-${index}" style="height:${48 + (index % 3) * 7}.4px">Message ${index}</article>`,
).join('');
const room = `<div class="chat-native__messages">${messages}</div><form class="chat-native__composer"><textarea>draft</textarea><button>send</button></form><div class="chat-native__end"></div>`;

const layouts = {
  desktopPadded: {
    viewport: { width: 1280, height: 900 },
    body: `<div class="scrollable chat-native" style="display:flex;flex-direction:column">${room}</div><div style="height:11.25px"></div>`,
  },
  mobileNavigation: {
    viewport: { width: 375, height: 667 },
    body: `<div class="scrollable chat-native" style="display:flex;flex-direction:column;padding-bottom:55px">${room}</div><div class="ui__navigation-bar" style="position:fixed;left:0;right:0;bottom:0;height:55px;background:#ccc">navigation</div>`,
  },
  column: {
    viewport: { width: 1280, height: 900 },
    body: `<div class="layout-multiple-columns"><div style="height:60px">header</div><div class="scrollable chat-native" style="display:flex;flex-direction:column;height:640px;overflow-y:auto">${room}</div><div style="height:200px">below</div></div>`,
  },
};

const measure = () => {
  const { distanceFromNewest, isAtNewest, rectVisible } = window.ScrollControl;
  const end = document.querySelector('.chat-native__end');
  const composer = document.querySelector('.chat-native__composer');
  const box = (element) => {
    const rect = element.getBoundingClientRect();
    return { top: rect.top, bottom: rect.bottom };
  };
  const column = document.querySelector('.chat-native');
  const nested =
    getComputedStyle(column).overflowY === 'auto' &&
    column.scrollHeight > column.clientHeight;
  const navigation = document
    .querySelector('.ui__navigation-bar')
    ?.getBoundingClientRect();
  const layout = {
    viewport: {
      innerHeight: window.innerHeight,
      rootClientHeight: document.documentElement.clientHeight,
      visual: window.visualViewport
        ? {
            height: window.visualViewport.height,
            offsetTop: window.visualViewport.offsetTop,
            scale: window.visualViewport.scale,
          }
        : null,
    },
    scroller: nested ? box(column) : null,
    navigation: navigation
      ? {
          top: navigation.top,
          bottom: navigation.bottom,
          height: navigation.height,
        }
      : null,
    composer: box(composer),
    end: box(end),
  };
  const last = document.getElementById('chat-message-39');
  return {
    distance: distanceFromNewest(layout),
    atNewest: isAtNewest(layout),
    lastVisible: rectVisible(layout, box(last)),
    lastAboveComposer: box(last).bottom <= box(composer).top + 0.5,
    composerResting: Math.abs(box(composer).bottom - box(end).top) <= 1,
  };
};

const alignEnd = () => {
  const end = document.querySelector('.chat-native__end');
  end.scrollIntoView({ block: 'end' });
  const column = document.querySelector('.chat-native');
  const scroller =
    getComputedStyle(column).overflowY === 'auto' &&
    column.scrollHeight > column.clientHeight
      ? column
      : document.scrollingElement;
  scroller.scrollTop = scroller.scrollHeight;
};

const scrollUp = (by) => {
  const column = document.querySelector('.chat-native');
  const scroller =
    getComputedStyle(column).overflowY === 'auto' &&
    column.scrollHeight > column.clientHeight
      ? column
      : document.scrollingElement;
  scroller.scrollTop -= by;
};

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
    for (const [layoutName, layout] of Object.entries(layouts)) {
      const page = await browser.newPage({ viewport: layout.viewport });
      await page.setContent(
        `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;font:16px sans-serif;--mobile-bottom-nav-height:55px}${css}</style><body>${layout.body}</body>`,
      );
      await page.addScriptTag({ content: control });
      await page.evaluate(alignEnd);
      const bottom = await page.evaluate(measure);
      await page.evaluate(scrollUp, 200);
      const up200 = await page.evaluate(measure);
      await page.evaluate(scrollUp, 100);
      const up300 = await page.evaluate(measure);
      await page.close();
      process.stdout.write(
        `${name} ${layoutName} ${JSON.stringify({ bottom, up200, up300 })}\n`,
      );
      assert.ok(bottom.atNewest, `${name} ${layoutName}: aligned is at newest`);
      assert.ok(bottom.lastVisible, `${name} ${layoutName}: last visible`);
      assert.ok(
        bottom.lastAboveComposer,
        `${name} ${layoutName}: last above composer`,
      );
      assert.ok(
        bottom.composerResting,
        `${name} ${layoutName}: composer resting above the end`,
      );
      assert.ok(
        Math.abs(up200.distance - bottom.distance - 200) <= 1,
        `${name} ${layoutName}: 200px up measures 200`,
      );
      assert.ok(!up200.atNewest && up200.distance < 240);
      assert.ok(up300.distance >= 240, `${name} ${layoutName}: 300px is away`);
      assert.ok(!up300.lastVisible, `${name} ${layoutName}: last hidden`);
    }
  } catch (error) {
    failed = true;
    console.error(name, error.message);
  } finally {
    await browser.close();
  }
}
if (failed) process.exitCode = 1;
