import type {
  Command,
  LayoutReading,
  ScrollEvent,
  ScrollState,
  Snapshot,
} from '../scroll_control';
import {
  distanceFromNewest,
  initialScrollState,
  isAtNewest,
  keyboardLift,
  rectVisible,
  revealAmount,
  step,
  visibleArea,
} from '../scroll_control';

// Geometry measured on the devices, from the diagnostics of f88ac08119 (/tmp/fediverse-continuation-20261106).
// iOS: ios-masto-diag/out/<se2|se3>/b-*.json `samples`; Android: android-masto-diag/raw/<galaxy|pixel>/*.json.
const device = {
  // iPhone SE 2nd generation, iOS 27.2: keyboard open at the newest (b-r3 t=9491).
  se2Keyboard: {
    viewport: {
      innerHeight: 287,
      rootClientHeight: 549,
      visual: { height: 287, offsetTop: 262, scale: 1 },
    },
    scroller: null,
    navigation: { top: 232, bottom: 287, height: 55 },
    composer: { top: 163, bottom: 232 },
    end: { top: 232.6, bottom: 232.6 },
  },
  // The same, after dragging up 80px with the keyboard open: innerHeight grows under it (b-r3 t=23912).
  se2KeyboardDrag1: {
    viewport: {
      innerHeight: 367,
      rootClientHeight: 549,
      visual: { height: 287, offsetTop: 182, scale: 1 },
    },
    scroller: null,
    navigation: { top: 312, bottom: 367, height: 55 },
    composer: { top: 243, bottom: 312 },
    end: { top: 312.6, bottom: 312.6 },
  },
  // Dragged up 80px more (b-r3 t=44416).
  se2KeyboardDrag2: {
    viewport: {
      innerHeight: 447,
      rootClientHeight: 549,
      visual: { height: 287, offsetTop: 102, scale: 1 },
    },
    scroller: null,
    navigation: { top: 392, bottom: 447, height: 55 },
    composer: { top: 323, bottom: 392 },
    end: { top: 392.6, bottom: 392.6 },
  },
  // iPhone SE 3rd generation, iOS 18.7.7: keyboard open at the newest (b-f1 t=13134).
  se3Keyboard: {
    viewport: {
      innerHeight: 320,
      rootClientHeight: 547,
      visual: { height: 320, offsetTop: 227, scale: 1 },
    },
    scroller: null,
    navigation: { top: 265, bottom: 320, height: 55 },
    composer: { top: 196, bottom: 265 },
    end: { top: 265.8, bottom: 265.8 },
  },
  // SE 2: Safari toolbar collapsed at the actual end of the page: scrollHeight−clientHeight−scrollTop = 40 (b-c2).
  se2Collapsed: {
    viewport: {
      innerHeight: 589,
      rootClientHeight: 549,
      visual: { height: 589, offsetTop: 0, scale: 1 },
    },
    scroller: null,
    navigation: { top: 533.5, bottom: 588.5, height: 55 },
    composer: { top: 464.5, bottom: 533.5 },
    end: { top: 534.6, bottom: 534.6 },
  },
  // SE 3: toolbar collapsed at the end, 77px by that formula (b-c2 t=35925).
  se3Collapsed: {
    viewport: {
      innerHeight: 625,
      rootClientHeight: 547,
      visual: { height: 625, offsetTop: 1, scale: 1 },
    },
    scroller: null,
    navigation: { top: 568.5, bottom: 623.5, height: 55 },
    composer: { top: 499.5, bottom: 568.5 },
    end: { top: 570.4, bottom: 570.4 },
  },
  // SE 3: the same page bouncing past its end while the toolbar collapses (b-c2 t=17027).
  se3Bounce: {
    viewport: {
      innerHeight: 625,
      rootClientHeight: 547,
      visual: { height: 625, offsetTop: 43.5, scale: 1 },
    },
    scroller: null,
    navigation: { top: 526, bottom: 581, height: 55 },
    composer: { top: 457, bottom: 526 },
    end: { top: 527.4, bottom: 527.4 },
  },
  // SE 3: read 33px up with the toolbar collapsed (b-c2 t=42307).
  se3CollapsedUp: {
    viewport: {
      innerHeight: 625,
      rootClientHeight: 547,
      visual: { height: 625, offsetTop: 0.5, scale: 1 },
    },
    scroller: null,
    navigation: { top: 569, bottom: 624, height: 55 },
    composer: { top: 500, bottom: 569 },
    end: { top: 603.4, bottom: 603.4 },
  },
  // Galaxy Z Flip3, Chrome 156: at the newest without the keyboard (k12-1 "pre").
  galaxy: {
    viewport: {
      innerHeight: 744,
      rootClientHeight: 744,
      visual: { height: 744.7, offsetTop: 0, scale: 1 },
    },
    scroller: null,
    navigation: { top: 689.7, bottom: 744.7, height: 55 },
    composer: { top: 620.7, bottom: 689.7 },
    end: { top: 690.6, bottom: 690.6 },
  },
  // Keyboard open: innerHeight stays, the visual viewport moves down by 324 (k12-1 "tap").
  galaxyKeyboard: {
    viewport: {
      innerHeight: 744,
      rootClientHeight: 744,
      visual: { height: 420.7, offsetTop: 324, scale: 1 },
    },
    scroller: null,
    navigation: { top: 689.7, bottom: 744.7, height: 55 },
    composer: { top: 620.7, bottom: 689.7 },
    end: { top: 690.6, bottom: 690.6 },
  },
  // Dragged up 85px with the keyboard open: only the visual viewport moves (k12-1 "drag1").
  galaxyKeyboardDrag1: {
    viewport: {
      innerHeight: 744,
      rootClientHeight: 744,
      visual: { height: 420.7, offsetTop: 238.3, scale: 1 },
    },
    scroller: null,
    navigation: { top: 689.7, bottom: 744.7, height: 55 },
    composer: { top: 620.7, bottom: 689.7 },
    end: { top: 690.6, bottom: 690.6 },
  },
  // Pixel 1, Chrome 156: keyboard open (k12-1 "tap") and dragged up (k12-1 "drag1").
  pixelKeyboard: {
    viewport: {
      innerHeight: 603,
      rootClientHeight: 603,
      visual: { height: 319.2, offsetTop: 284.2, scale: 1 },
    },
    scroller: null,
    navigation: { top: 548.9, bottom: 603.4, height: 54.5 },
    composer: { top: 479.7, bottom: 548.4 },
    end: { top: 549.8, bottom: 549.8 },
  },
  // Address bar collapsed at the actual end: scrollHeight−clientHeight−scrollTop = 56.5 (t5-1 "down").
  pixelCollapsed: {
    viewport: {
      innerHeight: 659,
      rootClientHeight: 603,
      visual: { height: 659.4, offsetTop: 0, scale: 1 },
    },
    scroller: null,
    navigation: { top: 604.9, bottom: 659.4, height: 54.5 },
    composer: { top: 535.7, bottom: 604.4 },
    end: { top: 605.8, bottom: 605.8 },
  },
  // Desktop Chromium on the review server: page padding below the end at the document's bottom (s2b-diag-8533).
  desktopPadded: {
    viewport: {
      innerHeight: 900,
      rootClientHeight: 900,
      visual: { height: 900, offsetTop: 0, scale: 1 },
    },
    scroller: null,
    navigation: { top: 0, bottom: 0, height: 0 },
    composer: { top: 819.8, bottom: 888.75 },
    end: { top: 888.75, bottom: 888.75 },
  },
} satisfies Record<string, LayoutReading>;

const lifted = (layout: LayoutReading): LayoutReading => {
  const lift = keyboardLift(layout.viewport);
  const navigation = layout.navigation && {
    ...layout.navigation,
    top: layout.navigation.top - lift,
    bottom: layout.navigation.bottom - lift,
  };
  const composer = layout.composer && {
    top: layout.composer.top - lift,
    bottom: layout.composer.bottom - lift,
  };
  return { ...layout, navigation, composer };
};

describe('The visible area', () => {
  it('uses the visual viewport as it is on iOS with the keyboard open (offsetTop 262 / 227)', () => {
    expect(visibleArea(device.se2Keyboard.viewport)).toMatchObject({
      top: 0,
      bottom: 287,
    });
    expect(visibleArea(device.se3Keyboard.viewport)).toMatchObject({
      top: 0,
      bottom: 320,
    });
  });

  it('stays on the screen while iOS grows innerHeight as the reader drags up with the keyboard open', () => {
    expect(visibleArea(device.se2KeyboardDrag1.viewport)).toMatchObject({
      top: 0,
      bottom: 287,
    });
    expect(visibleArea(device.se2KeyboardDrag2.viewport)).toMatchObject({
      top: 0,
      bottom: 287,
    });
  });

  it('follows the Android visual viewport within the layout viewport', () => {
    expect(visibleArea(device.galaxyKeyboard.viewport)).toMatchObject({
      top: 324,
      bottom: 744.7,
    });
    expect(visibleArea(device.galaxyKeyboardDrag1.viewport)).toMatchObject({
      top: 238.3,
      bottom: 659,
    });
    expect(visibleArea(device.pixelKeyboard.viewport).top).toBeCloseTo(284.2);
  });

  it('covers the screen with a collapsed toolbar, whatever offsetTop Safari reports', () => {
    expect(visibleArea(device.se3Collapsed.viewport)).toMatchObject({
      top: 0,
      bottom: 625,
    });
    expect(visibleArea(device.se3Bounce.viewport)).toMatchObject({
      top: 0,
      bottom: 625,
    });
    expect(visibleArea(device.pixelCollapsed.viewport)).toMatchObject({
      top: 0,
      bottom: 659.4,
    });
  });

  it('reports the zoom', () => {
    expect(
      visibleArea({
        innerHeight: 744,
        rootClientHeight: 744,
        visual: { height: 372, offsetTop: 120, scale: 2 },
      }),
    ).toMatchObject({ top: 120, bottom: 492, scale: 2 });
  });

  it('is the window without a visual viewport', () => {
    expect(
      visibleArea({ innerHeight: 768, rootClientHeight: 0, visual: null }),
    ).toEqual({ top: 0, bottom: 768, height: 768, scale: 1 });
  });
});

describe('Whether the newest message is in view', () => {
  it('is, at the end with the keyboard open on both iPhones', () => {
    expect(isAtNewest(device.se2Keyboard)).toBe(true);
    expect(isAtNewest(device.se3Keyboard)).toBe(true);
  });

  it('is, at the end of the page with a collapsed toolbar (40, 77 and 56.5px by the old formula)', () => {
    expect(isAtNewest(device.se2Collapsed)).toBe(true);
    expect(isAtNewest(device.se3Collapsed)).toBe(true);
    expect(isAtNewest(device.pixelCollapsed)).toBe(true);
  });

  it('is, while the end bounces with the toolbar collapsing', () => {
    expect(isAtNewest(device.se3Bounce)).toBe(true);
  });

  it('is, with page padding below the end at the bottom of a desktop document', () => {
    expect(distanceFromNewest(device.desktopPadded)).toBeCloseTo(-11.25);
    expect(isAtNewest(device.desktopPadded)).toBe(true);
  });

  it('is, on Android with and without the keyboard', () => {
    expect(isAtNewest(device.galaxy)).toBe(true);
    expect(isAtNewest(device.galaxyKeyboard)).toBe(true);
    expect(isAtNewest(device.pixelKeyboard)).toBe(true);
  });

  it('measures how far the reader went up, with the composer and navigation raised onto the visible bottom', () => {
    // iOS: 80px and 160px up.
    expect(distanceFromNewest(lifted(device.se2KeyboardDrag1))).toBeCloseTo(
      80.6,
    );
    expect(distanceFromNewest(lifted(device.se2KeyboardDrag2))).toBeCloseTo(
      160.6,
    );
    // Android: 85.7px up.
    expect(distanceFromNewest(lifted(device.galaxyKeyboardDrag1))).toBeCloseTo(
      85.9,
    );
    // Collapsed toolbar, 33px up.
    expect(distanceFromNewest(device.se3CollapsedUp)).toBeCloseTo(34.4);
    expect(isAtNewest(device.se3CollapsedUp)).toBe(false);
  });

  it('is cut by the room’s own scrolling box', () => {
    const inColumn: LayoutReading = {
      viewport: { innerHeight: 900, rootClientHeight: 900, visual: null },
      scroller: { top: 60, bottom: 700 },
      navigation: null,
      composer: { top: 600, bottom: 690 },
      end: { top: 760, bottom: 760 },
    };
    expect(distanceFromNewest(inColumn)).toBe(60);
    expect(isAtNewest(inColumn)).toBe(false);
  });
});

describe('Whether a message can be seen', () => {
  it('sees a message above the composer with the iOS keyboard open (it read nothing before: 262 > 163)', () => {
    expect(rectVisible(device.se2Keyboard, { top: 69.6, bottom: 144.4 })).toBe(
      true,
    );
    expect(rectVisible(device.se3Keyboard, { top: 90.8, bottom: 180.8 })).toBe(
      true,
    );
  });

  it('sees only what is within the Android visual viewport', () => {
    // Galaxy k3-1: the new message 550.9~605.7 under the keyboard-moved viewport 324~744.7.
    expect(
      rectVisible(device.galaxyKeyboard, { top: 550.9, bottom: 605.7 }),
    ).toBe(true);
    expect(rectVisible(device.galaxyKeyboard, { top: 200, bottom: 260 })).toBe(
      false,
    );
  });

  it('does not see what the composer covers', () => {
    expect(rectVisible(device.se2Keyboard, { top: 170, bottom: 220 })).toBe(
      false,
    );
  });

  it('sees nothing zoomed in', () => {
    expect(
      rectVisible(
        {
          ...device.galaxy,
          viewport: {
            ...device.galaxy.viewport,
            visual: { height: 372, offsetTop: 300, scale: 2 },
          },
        },
        { top: 550, bottom: 600 },
      ),
    ).toBe(false);
  });
});

describe('Raising the composer and navigation over the keyboard', () => {
  it('raises nothing when the keyboard just opened', () => {
    expect(keyboardLift(device.se2Keyboard.viewport)).toBe(0);
    expect(keyboardLift(device.galaxyKeyboard.viewport)).toBe(0);
  });

  it('raises by what iOS added below the visual viewport (80, 160)', () => {
    expect(keyboardLift(device.se2KeyboardDrag1.viewport)).toBe(80);
    expect(keyboardLift(device.se2KeyboardDrag2.viewport)).toBe(160);
  });

  it('raises by how far the Android visual viewport moved up (85.0, 84.6)', () => {
    expect(keyboardLift(device.galaxyKeyboardDrag1.viewport)).toBeCloseTo(85);
    expect(
      keyboardLift({
        ...device.pixelKeyboard.viewport,
        visual: { height: 319.2, offsetTop: 199.2, scale: 1 },
      }),
    ).toBeCloseTo(84.6);
  });
});

describe('Revealing the last message over the keyboard', () => {
  it('does not ask past the end of the page (iOS 27 SE 2 new message: 85.4 asked, 84 left)', () => {
    expect(
      revealAmount({
        last: { top: 55, bottom: 232.4 },
        composer: { top: 163, bottom: 232 },
        remaining: 3872 - 287 - 3501,
      }),
    ).toBe(84);
  });

  it('asks nothing at the end of the page, which Safari answered by shrinking (SE 3 delta 1.4)', () => {
    expect(
      revealAmount({
        last: { top: 90, bottom: 178.4375 },
        composer: { top: 193, bottom: 262 },
        remaining: 3562 - 317 - 3245,
      }),
    ).toBe(0);
  });

  it('asks nothing below a pixel', () => {
    expect(
      revealAmount({
        last: { top: 0, bottom: 147.6 },
        composer: { top: 163, bottom: 232 },
        remaining: 500,
      }),
    ).toBe(0);
  });
});

const snap = (over: Partial<Snapshot> = {}): Snapshot => ({
  scale: 1,
  height: 667,
  composerFocused: false,
  scrollTop: 0,
  distance: 0,
  reveal: 0,
  ...over,
});

const run = (
  state: ScrollState,
  events: [ScrollEvent, Partial<Snapshot>?][],
) => {
  let current = state;
  const commands: Command[] = [];
  for (const [event, over] of events) {
    const result = step(current, event, snap(over));
    current = result.state;
    commands.push(...result.commands);
  }
  return { state: current, commands };
};

const scrolls = (commands: Command[]) =>
  commands.filter((command) =>
    ['alignEnd', 'reveal', 'scrollToMessage', 'restoreScroll'].includes(
      command.type,
    ),
  );
const reads = (commands: Command[]) =>
  commands.filter((command) => command.type === 'read');
const lastAway = (commands: Command[]) =>
  commands
    .filter(
      (command): command is Extract<Command, { type: 'away' }> =>
        command.type === 'away',
    )
    .at(-1)?.value;

const opened = (target: string | null = null) =>
  run(initialScrollState(target), [
    [{ type: 'attached' }],
    [{ type: 'newestShown', screen: 'A:', mine: false }],
  ]);

const keyboardOpen = (state: ScrollState, over: Partial<Snapshot> = {}) =>
  run(state, [
    [
      { type: 'composerFocused' },
      { height: 549, scrollTop: 3501, composerFocused: true, ...over },
    ],
    [
      { type: 'viewportResized' },
      { height: 287, composerFocused: true, ...over },
    ],
  ]);

describe('Following the newest message (state table)', () => {
  it('1 opening a room follows and aligns to the newest', () => {
    const { state, commands } = opened();
    expect(state.following).toBe(true);
    expect(scrolls(commands)).toEqual([{ type: 'alignEnd' }]);
  });

  it('1 opening with the keyboard up reveals the last message instead of the page end', () => {
    const { commands } = run(initialScrollState(null), [
      [{ type: 'attached' }],
      [
        { type: 'newestShown', screen: 'A:', mine: false },
        { composerFocused: true, reveal: 36 },
      ],
    ]);
    expect(scrolls(commands)).toEqual([{ type: 'reveal', by: 36 }]);
  });

  it('2 opening at a searched message does not follow or scroll', () => {
    const { state, commands } = opened('m1');
    expect(state.following).toBe(false);
    expect(state.target).toEqual({
      id: 'm1',
      fromSearch: true,
      phase: 'seeking',
    });
    expect(scrolls(commands)).toEqual([]);
    expect(reads(commands)).toEqual([]);
  });

  it('3 a searched target that loads at once is scrolled to; away from the newest it does not follow', () => {
    const { state, commands } = run(opened('m1').state, [
      [{ type: 'targetLoaded', id: 'm1' }],
      [{ type: 'targetScrolled', id: 'm1', movedUp: true }, { distance: 1400 }],
    ]);
    expect(scrolls(commands)).toEqual([{ type: 'scrollToMessage', id: 'm1' }]);
    expect(state.following).toBe(false);
    expect(state.target?.phase).toBe('landed');
    expect(lastAway(commands)).toBe(true);
    expect(reads(commands)).toEqual([]);
  });

  it('3 a searched target at the newest follows and reads what is shown', () => {
    const { state, commands } = run(opened('m5').state, [
      [{ type: 'targetLoaded', id: 'm5' }],
      [{ type: 'targetScrolled', id: 'm5', movedUp: false }, { distance: 0 }],
    ]);
    expect(state.following).toBe(true);
    expect(reads(commands)).toEqual([{ type: 'read', kind: 'return' }]);
  });

  it('4 a searched target on an older page keeps being sought as pages arrive', () => {
    const { state, commands } = run(opened('m1').state, [
      [{ type: 'olderLoaded' }],
      [{ type: 'contentResized' }],
      [{ type: 'newestShown', screen: 'A:', mine: false }],
    ]);
    expect(state.target?.phase).toBe('seeking');
    expect(scrolls(commands)).toEqual([]);
  });

  it('5 a searched target that never comes aligns to the newest and reads it', () => {
    const { state, commands } = run(opened('gone').state, [
      [{ type: 'targetMissing' }],
    ]);
    expect(state.target).toBeNull();
    expect(state.following).toBe(true);
    expect(scrolls(commands)).toEqual([{ type: 'alignEnd' }]);
    expect(reads(commands)).toEqual([{ type: 'read', kind: 'newest' }]);
  });

  it('5 a quoted original that never comes stays where the reader is', () => {
    const { state, commands } = run(opened().state, [
      [{ type: 'quoteClicked', id: 'gone' }],
      [{ type: 'targetMissing' }],
    ]);
    expect(state.following).toBe(false);
    expect(state.target).toBeNull();
    expect(scrolls(commands)).toEqual([]);
  });

  it('6 a rate-limited older page leaves the target sought', () => {
    // Nothing is said to the scroll state: the target is sought again after the shared wait.
    const { state } = opened('m1');
    expect(state.target?.phase).toBe('seeking');
    expect(state.following).toBe(false);
  });

  it('7 a far quote stops following, shows the way back, and lands away', () => {
    const { state, commands } = run(opened().state, [
      [{ type: 'quoteClicked', id: 'm1' }],
      [{ type: 'targetLoaded', id: 'm1' }],
      [{ type: 'targetScrolled', id: 'm1', movedUp: true }, { distance: 1500 }],
    ]);
    expect(state.following).toBe(false);
    expect(lastAway(commands)).toBe(true);
    expect(scrolls(commands)).toEqual([{ type: 'scrollToMessage', id: 'm1' }]);
  });

  it('8 a quote whose original is already shown at the newest keeps following', () => {
    const { state } = run(opened().state, [
      [{ type: 'quoteClicked', id: 'm4' }],
      [{ type: 'targetLoaded', id: 'm4' }],
      [{ type: 'targetScrolled', id: 'm4', movedUp: false }, { distance: 0 }],
    ]);
    expect(state.following).toBe(true);
  });

  it('8 with page padding below the end (desktop, end 888.75 of 900) it keeps following', () => {
    const { state } = run(opened().state, [
      [{ type: 'quoteClicked', id: 'm4' }],
      [{ type: 'targetLoaded', id: 'm4' }],
      [
        { type: 'targetScrolled', id: 'm4', movedUp: false },
        { distance: distanceFromNewest(device.desktopPadded) },
      ],
    ]);
    expect(state.following).toBe(true);
  });

  it('9 tapping the same quote within its highlight changes nothing', () => {
    const landed = run(opened().state, [
      [{ type: 'quoteClicked', id: 'm4' }],
      [{ type: 'targetLoaded', id: 'm4' }],
      [{ type: 'targetScrolled', id: 'm4', movedUp: false }, { distance: 0 }],
    ]).state;
    const { state, commands } = run(landed, [
      [{ type: 'quoteClicked', id: 'm4' }],
      [{ type: 'targetLoaded', id: 'm4' }],
    ]);
    expect(state).toEqual(landed);
    expect(commands).toEqual([]);
  });

  it('10 a message arriving while the original is sought is not followed', () => {
    const { commands } = run(opened().state, [
      [{ type: 'quoteClicked', id: 'm1' }],
      [{ type: 'newestShown', screen: 'A:', mine: false }],
      [{ type: 'contentResized' }],
    ]);
    expect(scrolls(commands)).toEqual([]);
  });

  it('11 the highlight ending moves nothing', () => {
    const { state, commands } = run(opened().state, [
      [{ type: 'quoteClicked', id: 'm4' }],
      [{ type: 'targetLoaded', id: 'm4' }],
      [{ type: 'targetScrolled', id: 'm4', movedUp: true }, { distance: 120 }],
      [{ type: 'timer', name: 'ownJumpEnd' }],
      [{ type: 'timer', name: 'highlightEnd' }, { distance: 120 }],
    ]);
    expect(state.target).toBeNull();
    expect(state.following).toBe(false);
    expect(scrolls(commands)).toEqual([{ type: 'scrollToMessage', id: 'm4' }]);
  });

  it('12 scrolling up past 240px stops following; back within it follows and reads', () => {
    const away = run(opened().state, [
      [{ type: 'scrolled' }, { distance: 300 }],
    ]);
    expect(away.state.following).toBe(false);
    expect(lastAway(away.commands)).toBe(true);
    const back = run(away.state, [[{ type: 'scrolled' }, { distance: 200 }]]);
    expect(back.state.following).toBe(true);
    expect(reads(back.commands)).toEqual([{ type: 'read', kind: 'return' }]);
  });

  it('12 measures the 240px with the collapsed-toolbar geometry (SE 3, 34.4px up)', () => {
    const { state } = run(opened().state, [
      [
        { type: 'scrolled' },
        { distance: distanceFromNewest(device.se3CollapsedUp) },
      ],
    ]);
    expect(state.following).toBe(true);
  });

  it('13 the reader scrolling while an original is sought cancels it', () => {
    const { state, commands } = run(opened().state, [
      [{ type: 'quoteClicked', id: 'm1' }],
      [{ type: 'userIntent' }],
      [{ type: 'targetLoaded', id: 'm1' }],
    ]);
    expect(state.target).toBeNull();
    expect(state.following).toBe(false);
    expect(scrolls(commands)).toEqual([]);
  });

  it('14 the scroll events of a jump measure the newest exactly, not by 240px', () => {
    const { state } = run(opened().state, [
      [{ type: 'quoteClicked', id: 'm4' }],
      [{ type: 'targetLoaded', id: 'm4' }],
      [{ type: 'targetScrolled', id: 'm4', movedUp: false }, { distance: 0 }],
      [{ type: 'scrolled' }, { distance: 120 }],
    ]);
    expect(state.following).toBe(false);
  });

  it('15 the newest button follows, aligns, reads and cancels a sought original', () => {
    const { state, commands } = run(opened().state, [
      [{ type: 'quoteClicked', id: 'm1' }],
      [{ type: 'jumpToNewest' }, { distance: 2000 }],
    ]);
    expect(state.target).toBeNull();
    expect(state.following).toBe(true);
    expect(lastAway(commands)).toBe(false);
    expect(scrolls(commands)).toEqual([{ type: 'alignEnd' }]);
    expect(reads(commands)).toEqual([{ type: 'read', kind: 'return' }]);
  });

  it('16 a new message, or mine, is followed while following', () => {
    for (const mine of [false, true]) {
      const { commands } = run(opened().state, [
        [{ type: 'newestShown', screen: 'A:', mine }],
      ]);
      expect(scrolls(commands)).toEqual([{ type: 'alignEnd' }]);
    }
  });

  it('17 a new message, or mine, leaves the reader of older ones where they are', () => {
    for (const mine of [false, true]) {
      const { commands } = run(opened().state, [
        [{ type: 'scrolled' }, { distance: 3000 }],
        [{ type: 'newestShown', screen: 'A:', mine }],
        [{ type: 'contentResized' }],
      ]);
      expect(scrolls(commands)).toEqual([]);
    }
  });

  it('18 a new message during a highlight at the newest is followed', () => {
    const { commands } = run(opened().state, [
      [{ type: 'quoteClicked', id: 'm4' }],
      [{ type: 'targetLoaded', id: 'm4' }],
      [{ type: 'targetScrolled', id: 'm4', movedUp: false }, { distance: 0 }],
      [{ type: 'newestShown', screen: 'A:', mine: true }],
    ]);
    expect(scrolls(commands).at(-1)).toEqual({ type: 'alignEnd' });
  });

  it('19 opening the keyboard records the place and raises the composer', () => {
    const { state, commands } = keyboardOpen(opened().state);
    expect(state.keyboard).toMatchObject({
      restoreTop: 3501,
      following: true,
      baseHeight: 549,
    });
    expect(commands).toContainEqual({ type: 'lift', on: true });
  });

  it('20 the keyboard opening at the end of the page asks no scroll (SE 3 delta 1.4, nothing left)', () => {
    const reveal = revealAmount({
      last: { top: 90, bottom: 178.4375 },
      composer: { top: 193, bottom: 262 },
      remaining: 0,
    });
    const { commands } = keyboardOpen(opened().state, { reveal });
    expect(scrolls(commands)).toEqual([]);
  });

  it('20 a new message over the keyboard is revealed by what is left of the page (84 of 85.4)', () => {
    const reveal = revealAmount({
      last: { top: 55, bottom: 232.4 },
      composer: { top: 163, bottom: 232 },
      remaining: 84,
    });
    const { state } = keyboardOpen(opened().state);
    const { commands } = run(state, [
      [
        { type: 'newestShown', screen: 'A:', mine: false },
        { height: 287, composerFocused: true, reveal },
      ],
    ]);
    expect(scrolls(commands)).toEqual([{ type: 'reveal', by: 84 }]);
  });

  it('21 a drag up with the keyboard open stops following and records where the reader is', () => {
    const { state } = keyboardOpen(opened().state);
    const dragged = run(state, [
      [{ type: 'userIntent' }],
      [
        { type: 'scrolled' },
        {
          height: 287,
          composerFocused: true,
          scrollTop: 3253,
          distance: distanceFromNewest(lifted(device.se2KeyboardDrag2)),
        },
      ],
    ]);
    // 160px up is still within 240px.
    expect(dragged.state.following).toBe(true);
    const further = run(dragged.state, [
      [
        { type: 'scrolled' },
        {
          height: 287,
          composerFocused: true,
          scrollTop: 3150,
          distance: 300,
        },
      ],
      [
        { type: 'scrollEnded' },
        {
          height: 287,
          composerFocused: true,
          scrollTop: 3100,
          distance: 350,
        },
      ],
    ]);
    expect(further.state.following).toBe(false);
    expect(further.state.keyboard).toMatchObject({
      restoreTop: 3100,
      following: false,
    });
  });

  it('21 a scroll Safari makes by itself with the keyboard open is not the reader’s', () => {
    const { state } = keyboardOpen(opened().state);
    const { state: after } = run(state, [
      [
        { type: 'scrolled' },
        { height: 287, composerFocused: true, distance: 900 },
      ],
    ]);
    expect(after.following).toBe(true);
  });

  it('22 the Android visual viewport moving with a finger raises the composer and tracks the reader', () => {
    const { state } = keyboardOpen(opened().state, { height: 420.7 });
    const { state: after, commands } = run(state, [
      [{ type: 'userIntent' }],
      [
        { type: 'viewportScrolled' },
        {
          height: 420.7,
          composerFocused: true,
          distance: distanceFromNewest(lifted(device.galaxyKeyboardDrag1)),
        },
      ],
    ]);
    expect(commands).toContainEqual({ type: 'lift', on: true });
    expect(after.following).toBe(true);
    expect(reads(commands)).toContainEqual({ type: 'read', kind: 'check' });
  });

  it('23 closing the keyboard while following aligns to the newest', () => {
    const { state } = keyboardOpen(opened().state);
    const { state: after, commands } = run(state, [
      [{ type: 'composerBlurred' }],
      [{ type: 'timer', name: 'keyboardClose' }, { height: 549 }],
    ]);
    expect(after.keyboard).toBeNull();
    expect(scrolls(commands)).toEqual([{ type: 'alignEnd' }]);
    expect(commands).toContainEqual({ type: 'lift', on: false });
  });

  it('24 closing the keyboard while reading older ones goes back to where inertia ended', () => {
    const away = run(opened().state, [
      [{ type: 'scrolled' }, { distance: 3000 }],
    ]).state;
    const { state } = keyboardOpen(away, { scrollTop: 250 });
    const { state: after, commands } = run(state, [
      [{ type: 'userIntent' }],
      [{ type: 'scrolled' }, { distance: 3000, scrollTop: 300 }],
      [{ type: 'scrolled' }, { distance: 3000, scrollTop: 275 }],
      [{ type: 'timer', name: 'userScrollEnd' }],
      [{ type: 'composerBlurred' }],
      [{ type: 'timer', name: 'keyboardClose' }, { height: 667 }],
    ]);
    expect(scrolls(commands)).toEqual([{ type: 'restoreScroll', top: 275 }]);
    expect(after.following).toBe(false);
  });

  it('24 the keyboard closing by its height coming back is detected too', () => {
    const away = run(opened().state, [
      [{ type: 'scrolled' }, { distance: 3000 }],
    ]).state;
    const { state } = keyboardOpen(away, { scrollTop: 250 });
    const { commands } = run(state, [
      [{ type: 'viewportResized' }, { height: 549, composerFocused: true }],
    ]);
    expect(commands).toContainEqual({
      type: 'timer',
      name: 'keyboardClose',
      delay: 200,
    });
  });

  it('25 a jump or the newest button with the keyboard open is not undone when it closes', () => {
    const away = run(opened().state, [
      [{ type: 'scrolled' }, { distance: 3000 }],
    ]).state;
    for (const explicit of [
      [
        [{ type: 'quoteClicked', id: 'm1' }],
        [{ type: 'targetLoaded', id: 'm1' }],
        [
          { type: 'targetScrolled', id: 'm1', movedUp: true },
          { distance: 1500 },
        ],
      ],
      [[{ type: 'jumpToNewest' }]],
      [[{ type: 'pageAction' }]],
    ] as [ScrollEvent, Partial<Snapshot>?][][]) {
      const { state } = keyboardOpen(away, { scrollTop: 250 });
      const { commands } = run(state, [
        ...explicit,
        [{ type: 'composerBlurred' }],
        [{ type: 'timer', name: 'keyboardClose' }, { height: 667 }],
      ]);
      expect(
        scrolls(commands).filter((command) => command.type === 'restoreScroll'),
      ).toEqual([]);
    }
  });

  it('26 scrolling while zoomed stops following and cancels going back after the keyboard', () => {
    const { state } = keyboardOpen(opened().state);
    const { state: after, commands } = run(state, [
      [{ type: 'scrolled' }, { scale: 2, distance: 400 }],
      [{ type: 'newestShown', screen: 'A:', mine: false }, { scale: 2 }],
    ]);
    expect(after.following).toBe(false);
    expect(after.zoomedAway).toBe(true);
    expect(after.keyboard?.restoreTop).toBeNull();
    expect(scrolls(commands)).toEqual([]);
  });

  it('26 a message arriving zoomed in is not followed even while following', () => {
    const { commands } = run(opened().state, [
      [{ type: 'newestShown', screen: 'A:', mine: false }, { scale: 2 }],
      [{ type: 'contentResized' }, { scale: 2 }],
    ]);
    expect(scrolls(commands)).toEqual([]);
  });

  it('27 unzooming at the newest follows again, measured with the collapsed toolbar (Pixel 56.5px)', () => {
    const { state, commands } = run(opened().state, [
      [{ type: 'viewportResized' }, { scale: 2 }],
      [{ type: 'scrolled' }, { scale: 2 }],
      [
        { type: 'viewportResized' },
        { scale: 1, distance: distanceFromNewest(device.pixelCollapsed) },
      ],
    ]);
    expect(state.following).toBe(true);
    expect(reads(commands)).toContainEqual({ type: 'read', kind: 'return' });
  });

  it('27 unzooming away from the newest keeps the place', () => {
    const { state } = run(opened().state, [
      [{ type: 'viewportResized' }, { scale: 2 }],
      [{ type: 'scrolled' }, { scale: 2 }],
      [{ type: 'viewportResized' }, { scale: 1, distance: 600 }],
    ]);
    expect(state.following).toBe(false);
  });

  it('28 the screen changing size realigns only while following', () => {
    const following = run(opened().state, [
      [{ type: 'viewportResized' }, { height: 500 }],
    ]);
    expect(scrolls(following.commands)).toEqual([{ type: 'alignEnd' }]);
    const away = run(opened().state, [
      [{ type: 'scrolled' }, { distance: 3000 }],
      [{ type: 'viewportResized' }, { height: 500 }],
    ]);
    expect(scrolls(away.commands)).toEqual([]);
  });

  it('28 a pinch zoom changing the height does not realign', () => {
    const { commands } = run(opened().state, [
      [{ type: 'viewportResized' }, { scale: 2, height: 333 }],
      [{ type: 'viewportResized' }, { scale: 1, height: 667 }],
    ]);
    expect(scrolls(commands)).toEqual([]);
  });

  it('29 content growing keeps the newest in view while following, and checks what is seen', () => {
    const { commands } = run(opened().state, [[{ type: 'contentResized' }]]);
    expect(scrolls(commands)).toEqual([{ type: 'alignEnd' }]);
    expect(reads(commands)).toEqual([{ type: 'read', kind: 'check' }]);
  });

  it('30 loading older messages moves nothing', () => {
    const away = run(opened().state, [
      [{ type: 'scrolled' }, { distance: 3000 }],
    ]).state;
    const { state, commands } = run(away, [[{ type: 'olderLoaded' }]]);
    expect(state).toEqual(away);
    expect(commands).toEqual([]);
  });

  it('31 nothing pulls the reader down while they scroll; following again after it, the newest is aligned', () => {
    // Pixel: dragging down at the collapsed-toolbar end re-expands it and resizes the viewport 12 times.
    const dragging = run(opened().state, [
      [{ type: 'userIntent' }],
      [{ type: 'viewportResized' }, { height: 640 }],
      [{ type: 'scrolled' }, { distance: 7 }],
      [{ type: 'viewportResized' }, { height: 620 }],
      [{ type: 'newestShown', screen: 'A:', mine: false }],
      [{ type: 'contentResized' }],
    ]);
    expect(scrolls(dragging.commands)).toEqual([]);
    expect(dragging.state.pendingFollow).toBe(true);
    const ended = run(dragging.state, [
      [{ type: 'timer', name: 'userScrollEnd' }, { distance: 7 }],
    ]);
    expect(scrolls(ended.commands)).toEqual([{ type: 'alignEnd' }]);
  });

  it('31 a toolbar coming back as the reader drags is not undone after the drag either', () => {
    // Pixel t5: 70px down at the collapsed-toolbar end; only the viewport resizes.
    const { state, commands } = run(opened().state, [
      [{ type: 'userIntent' }],
      [{ type: 'viewportResized' }, { height: 640 }],
      [{ type: 'scrolled' }, { distance: 40 }],
      [{ type: 'viewportResized' }, { height: 603.4 }],
      [{ type: 'scrolled' }, { distance: 70 }],
      [{ type: 'timer', name: 'userScrollEnd' }, { distance: 70 }],
    ]);
    expect(state.following).toBe(true);
    expect(scrolls(commands)).toEqual([]);
  });

  it('31 what waited is dropped when the reader ends up reading older ones', () => {
    const { commands } = run(opened().state, [
      [{ type: 'userIntent' }],
      [{ type: 'newestShown', screen: 'A:', mine: false }],
      [{ type: 'scrolled' }, { distance: 600 }],
      [{ type: 'scrollEnded' }, { distance: 600 }],
    ]);
    expect(scrolls(commands)).toEqual([]);
  });

  it('32 Safari answering a reveal by shrinking its viewport is not answered again', () => {
    // iOS 27 SE 2 n1: the reveal of 84 at 287, then Safari shrinks the viewport 1px at a time.
    const { state } = keyboardOpen(opened().state);
    const revealed = run(state, [
      [
        { type: 'newestShown', screen: 'A:', mine: false },
        { height: 287, composerFocused: true, reveal: 84 },
      ],
    ]);
    const echoed = run(revealed.state, [
      [
        { type: 'viewportResized' },
        { height: 286, composerFocused: true, reveal: 1.4 },
      ],
      [
        { type: 'viewportResized' },
        { height: 286, composerFocused: true, reveal: 1.4 },
      ],
    ]);
    expect(scrolls(echoed.commands)).toEqual([]);
  });

  it('32 a real resize after the echo window is answered', () => {
    const { state } = keyboardOpen(opened().state);
    const { commands } = run(state, [
      [
        { type: 'newestShown', screen: 'A:', mine: false },
        { height: 287, composerFocused: true, reveal: 84 },
      ],
      [{ type: 'timer', name: 'echoEnd' }],
      [
        { type: 'viewportResized' },
        { height: 250, composerFocused: true, reveal: 30 },
      ],
    ]);
    expect(scrolls(commands).at(-1)).toEqual({ type: 'reveal', by: 30 });
  });

  it('33 a reveal of less than a pixel is not asked', () => {
    const { state } = keyboardOpen(opened().state);
    const { commands } = run(state, [
      [
        { type: 'newestShown', screen: 'A:', mine: false },
        { height: 287, composerFocused: true, reveal: 0 },
      ],
    ]);
    expect(scrolls(commands)).toEqual([]);
  });

  it('34 leaving the screen ends the keyboard and puts the composer back, keeping the rest', () => {
    const { state } = keyboardOpen(opened().state);
    const { state: after, commands } = run(state, [[{ type: 'detached' }]]);
    expect(after.keyboard).toBeNull();
    expect(after.following).toBe(true);
    expect(commands).toContainEqual({ type: 'lift', on: false });
  });

  it('34 coming back to the room view follows the newest again', () => {
    const { state, commands } = run(opened().state, [
      [{ type: 'scrolled' }, { distance: 3000 }],
      [{ type: 'detached' }],
      [{ type: 'attached' }],
      [{ type: 'newestShown', screen: 'A:members', mine: false }],
      [{ type: 'newestShown', screen: 'A:', mine: false }],
    ]);
    expect(state.following).toBe(true);
    expect(scrolls(commands).at(-1)).toEqual({ type: 'alignEnd' });
  });

  it('never follows while an original is sought', () => {
    const events: ScrollEvent[] = [
      { type: 'newestShown', screen: 'A:', mine: false },
      { type: 'contentResized' },
      { type: 'viewportResized' },
      { type: 'scrolled' },
    ];
    let { state } = opened('m1');
    for (const event of events) {
      state = step(state, event, snap({ distance: 0, height: 500 })).state;
      expect(state.following).toBe(false);
    }
  });
});
