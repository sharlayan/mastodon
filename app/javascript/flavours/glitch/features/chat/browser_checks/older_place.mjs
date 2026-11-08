// Run from the repository root with `node .../older_place.mjs`.
// Draws a room with React, the chat's own styles and the real scroll hook in Chromium and WebKit, reads up to the top
// as someone about to load older messages does, puts 40 older messages in above, and checks that the message being
// read stays where it was on the screen (rule 5; review f35f D2 measured +2,700~3,100px on the review server).
// CHAT_SCROLL_HOOK may point at another use_chat_scroll.ts to compare.
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
const hook = path.resolve(
  process.env.CHAT_SCROLL_HOOK ??
    'app/javascript/flavours/glitch/features/chat/use_chat_scroll.ts',
);

const app = (
  await esbuild.build({
    stdin: {
      contents: `
import { useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { createChatScroll, useChatScroll } from ${JSON.stringify(hook)};

const range = (from, to) => Array.from({ length: to - from }, (_, i) => from + i);
const nothing = () => undefined;

const Room = () => {
  const [scroll] = useState(() => createChatScroll(null));
  // Stable, as the room's own (index.tsx keeps it in state).
  const [jumpButton] = useState(() => ({ update: nothing }));
  const [ids, setIds] = useState(() => range(40, 80));
  const endRef = useRef(null);
  const listRef = useRef(null);
  const composerRef = useRef(null);
  useChatScroll(scroll, {
    endRef, listRef, composerRef,
    jumpButton,
    attachKey: 'room',
    screen: 'room:',
    newestId: String(ids.at(-1)),
    newestIsMine: false,
    oldestId: String(ids[0]),
    targetShown: false,
    onReadCheck: nothing, onReturn: nothing, onReadNewest: nothing,
  });
  window.loadOlder = () => {
    scroll.dispatch({ type: 'olderArriving' });
    setIds((current) => [...range(0, 40), ...current]);
  };
  window.following = () => scroll.following();
  return (
    <>
      <button type='button' className='load-more'>Load more</button>
      <div className='chat-native__messages' ref={listRef}>
        {ids.map((id) => (
          <article key={id} id={'chat-message-' + id} className='chat-native__message' style={{ height: 48 + (id % 3) * 7.4 + 'px' }}>
            Message {id}
          </article>
        ))}
      </div>
      <form className='chat-native__composer' ref={composerRef}><textarea defaultValue='draft' /></form>
      <div className='chat-native__end' ref={endRef} />
    </>
  );
};

createRoot(document.getElementById('room')).render(<Room />);
`,
      loader: 'tsx',
      resolveDir: path.resolve('.'),
    },
    bundle: true,
    format: 'iife',
    jsx: 'automatic',
    define: { 'process.env.NODE_ENV': '"production"' },
    write: false,
    logLevel: 'error',
  })
).outputFiles[0].text;

const layouts = {
  desktop: {
    viewport: { width: 1280, height: 900 },
    body: `<div id="room" class="scrollable chat-native" style="display:flex;flex-direction:column"></div><div style="height:11.25px"></div>`,
  },
  mobileNavigation: {
    viewport: { width: 375, height: 667 },
    body: `<div id="room" class="scrollable chat-native" style="display:flex;flex-direction:column;padding-bottom:55px"></div><div class="ui__navigation-bar" style="position:fixed;left:0;right:0;bottom:0;height:55px;background:#ccc">navigation</div>`,
  },
  column: {
    viewport: { width: 1280, height: 900 },
    body: `<div class="layout-multiple-columns"><div style="height:60px">header</div><div id="room" class="scrollable chat-native" style="display:flex;flex-direction:column;height:640px;overflow-y:auto"></div></div>`,
  },
};

const scroller = () => {
  const column = document.getElementById('room');
  return getComputedStyle(column).overflowY === 'auto' &&
    column.scrollHeight > column.clientHeight
    ? column
    : document.scrollingElement;
};
const frames = () =>
  new Promise((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(resolve));
  });

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
      await page.addScriptTag({ content: app });
      await page.waitForSelector('#chat-message-79');
      const result = await page.evaluate(
        async ([scrollerSource, framesSource]) => {
          const findScroller = new Function(`return (${scrollerSource})()`);
          const waitFrames = new Function(`return (${framesSource})()`);
          await waitFrames();
          const openedFollowing = window.following();
          // Read up to the top, where the button to load older messages is.
          findScroller().scrollTop = 0;
          await waitFrames();
          const reading = document.getElementById('chat-message-40');
          const before = reading.getBoundingClientRect().top;
          const awayBefore = !window.following();
          window.loadOlder();
          await waitFrames();
          const after = document
            .getElementById('chat-message-40')
            .getBoundingClientRect().top;
          return {
            openedFollowing,
            awayBefore,
            before,
            after,
            moved: after - before,
            scrollTop: findScroller().scrollTop,
            olderShown: Boolean(document.getElementById('chat-message-0')),
          };
        },
        [scroller.toString(), frames.toString()],
      );
      await page.close();
      process.stdout.write(`${name} ${layoutName} ${JSON.stringify(result)}\n`);
      assert.ok(
        result.openedFollowing,
        `${name} ${layoutName}: opened following`,
      );
      assert.ok(result.awayBefore, `${name} ${layoutName}: reading older ones`);
      assert.ok(result.olderShown, `${name} ${layoutName}: older drawn`);
      assert.ok(
        Math.abs(result.moved) <= 1,
        `${name} ${layoutName}: the message being read stays (moved ${result.moved})`,
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
