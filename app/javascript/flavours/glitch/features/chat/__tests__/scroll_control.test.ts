import type {
  Box,
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
  keyboardRoom,
  rectShown,
  rectVisible,
  revealAmount,
  step,
  viewportRestsOnKeyboard,
  visibleArea,
} from '../scroll_control';

const device = {
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
  const lift = keyboardLift(layout.viewport, true);
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
    expect(distanceFromNewest(lifted(device.se2KeyboardDrag1))).toBeCloseTo(
      80.6,
    );
    expect(distanceFromNewest(lifted(device.se2KeyboardDrag2))).toBeCloseTo(
      160.6,
    );
    expect(distanceFromNewest(lifted(device.galaxyKeyboardDrag1))).toBeCloseTo(
      85.9,
    );
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

const galaxyOpening = {
  innerHeight: 744,
  rootClientHeight: 744,
  visual: { height: 420.7, offsetTop: 0, scale: 1 },
};
const pixelOpening = {
  innerHeight: 603,
  rootClientHeight: 603,
  visual: { height: 319.2, offsetTop: 0, scale: 1 },
};

describe('Raising the composer and navigation over the keyboard', () => {
  it('raises nothing when the keyboard just opened', () => {
    expect(keyboardLift(device.se2Keyboard.viewport, false)).toBe(0);
    expect(keyboardLift(device.galaxyKeyboard.viewport, true)).toBe(0);
  });

  it('raises by what iOS added below the visual viewport (80, 160), at any time', () => {
    expect(keyboardLift(device.se2KeyboardDrag1.viewport, false)).toBe(80);
    expect(keyboardLift(device.se2KeyboardDrag2.viewport, false)).toBe(160);
  });

  it('raises by how far the Android visual viewport moved up (85.0, 84.6) once it has rested on the keyboard', () => {
    expect(keyboardLift(device.galaxyKeyboardDrag1.viewport, true)).toBeCloseTo(
      85,
    );
    expect(
      keyboardLift(
        {
          ...device.pixelKeyboard.viewport,
          visual: { height: 319.2, offsetTop: 199.2, scale: 1 },
        },
        true,
      ),
    ).toBeCloseTo(84.6);
  });

  it('raises nothing while Chrome is still to bring the visual viewport down (323.3 and 283.8 on f35f1ec)', () => {
    expect(keyboardLift(galaxyOpening, false)).toBe(0);
    expect(keyboardLift(pixelOpening, false)).toBe(0);
    expect(keyboardLift(galaxyOpening, true)).toBeCloseTo(323.3);
    expect(viewportRestsOnKeyboard(galaxyOpening)).toBe(false);
    expect(viewportRestsOnKeyboard(device.galaxyKeyboard.viewport)).toBe(true);
    expect(viewportRestsOnKeyboard(device.pixelKeyboard.viewport)).toBe(true);
    expect(viewportRestsOnKeyboard(device.galaxy.viewport)).toBe(false);
    expect(viewportRestsOnKeyboard(device.se2Keyboard.viewport)).toBe(false);
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
  viewport: {
    innerHeight: 667,
    rootClientHeight: 667,
    visual: {
      height: over.height ?? 667,
      offsetTop: 0,
      scale: over.scale ?? 1,
    },
  },
  ownScroller: false,
  firstMessage: null,
  messageTop: () => null,
  messageShown: () => false,
  remaining: 0,
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
      [
        { type: 'targetScrolled', id: 'm1', movedUp: true, moved: true },
        { distance: 1400 },
      ],
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
      [
        { type: 'targetScrolled', id: 'm5', movedUp: false, moved: false },
        { distance: 0 },
      ],
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
    const { state } = opened('m1');
    expect(state.target?.phase).toBe('seeking');
    expect(state.following).toBe(false);
  });

  it('7 a far quote stops following, shows the way back, and lands away', () => {
    const { state, commands } = run(opened().state, [
      [{ type: 'quoteClicked', id: 'm1' }],
      [{ type: 'targetLoaded', id: 'm1' }],
      [
        { type: 'targetScrolled', id: 'm1', movedUp: true, moved: true },
        { distance: 1500 },
      ],
    ]);
    expect(state.following).toBe(false);
    expect(lastAway(commands)).toBe(true);
    expect(scrolls(commands)).toEqual([{ type: 'scrollToMessage', id: 'm1' }]);
  });

  it('8 a quote whose original is already shown at the newest keeps following', () => {
    const { state } = run(opened().state, [
      [{ type: 'quoteClicked', id: 'm4' }],
      [{ type: 'targetLoaded', id: 'm4' }],
      [
        { type: 'targetScrolled', id: 'm4', movedUp: false, moved: false },
        { distance: 0 },
      ],
    ]);
    expect(state.following).toBe(true);
  });

  it('8 with page padding below the end (desktop, end 888.75 of 900) it keeps following', () => {
    const { state } = run(opened().state, [
      [{ type: 'quoteClicked', id: 'm4' }],
      [{ type: 'targetLoaded', id: 'm4' }],
      [
        { type: 'targetScrolled', id: 'm4', movedUp: false, moved: false },
        { distance: distanceFromNewest(device.desktopPadded) },
      ],
    ]);
    expect(state.following).toBe(true);
  });

  it('9 tapping the same quote within its highlight changes nothing', () => {
    const landed = run(opened().state, [
      [{ type: 'quoteClicked', id: 'm4' }],
      [{ type: 'targetLoaded', id: 'm4' }],
      [
        { type: 'targetScrolled', id: 'm4', movedUp: false, moved: false },
        { distance: 0 },
      ],
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
      [
        { type: 'targetScrolled', id: 'm4', movedUp: true, moved: true },
        { distance: 120 },
      ],
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
      [{ type: 'userIntent', touch: false }],
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
      [
        { type: 'targetScrolled', id: 'm4', movedUp: false, moved: false },
        { distance: 0 },
      ],
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
      [
        { type: 'targetScrolled', id: 'm4', movedUp: false, moved: false },
        { distance: 0 },
      ],
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
    expect(
      commands.some(
        (command) => command.type === 'lift' && command.by !== null,
      ),
    ).toBe(true);
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
      [{ type: 'userIntent', touch: false }],
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
      [{ type: 'userIntent', touch: false }],
      [
        { type: 'viewportScrolled' },
        {
          height: 420.7,
          composerFocused: true,
          distance: distanceFromNewest(lifted(device.galaxyKeyboardDrag1)),
        },
      ],
    ]);
    expect(
      commands.some(
        (command) => command.type === 'lift' && command.by !== null,
      ),
    ).toBe(true);
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
    expect(commands).toContainEqual({ type: 'lift', by: null });
  });

  it('24 closing the keyboard while reading older ones goes back to where inertia ended', () => {
    const away = run(opened().state, [
      [{ type: 'scrolled' }, { distance: 3000 }],
    ]).state;
    const { state } = keyboardOpen(away, { scrollTop: 250 });
    const { state: after, commands } = run(state, [
      [{ type: 'userIntent', touch: false }],
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
          { type: 'targetScrolled', id: 'm1', movedUp: true, moved: true },
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
    const dragging = run(opened().state, [
      [{ type: 'userIntent', touch: false }],
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
    const { state, commands } = run(opened().state, [
      [{ type: 'userIntent', touch: false }],
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
      [{ type: 'userIntent', touch: false }],
      [{ type: 'newestShown', screen: 'A:', mine: false }],
      [{ type: 'scrolled' }, { distance: 600 }],
      [{ type: 'scrollEnded' }, { distance: 600 }],
    ]);
    expect(scrolls(commands)).toEqual([]);
  });

  it('32 Safari answering a reveal by shrinking its viewport is not answered again', () => {
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
    expect(commands).toContainEqual({ type: 'lift', by: null });
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

const liftAmounts = (commands: Command[]) =>
  commands
    .filter(
      (command): command is Extract<Command, { type: 'lift' }> =>
        command.type === 'lift',
    )
    .map((command) => command.by);

describe('Following the newest message (state table, after f35f1ec)', () => {
  for (const [name, before, opening, rested, dragged, lift] of [
    [
      'Galaxy',
      device.galaxy.viewport,
      galaxyOpening,
      device.galaxyKeyboard.viewport,
      device.galaxyKeyboardDrag1.viewport,
      85,
    ],
    [
      'Pixel',
      {
        innerHeight: 603,
        rootClientHeight: 603,
        visual: { height: 603.4, offsetTop: 0, scale: 1 },
      },
      pixelOpening,
      device.pixelKeyboard.viewport,
      {
        ...device.pixelKeyboard.viewport,
        visual: { height: 319.2, offsetTop: 199.6, scale: 1 },
      },
      84.2,
    ],
  ] as const) {
    it(`35 an Android keyboard opening raises nothing until Chrome has brought the view down (${name})`, () => {
      const at = (viewport: typeof before) => ({
        viewport,
        height: viewport.visual.height,
        composerFocused: true,
      });
      const { commands } = run(opened().state, [
        [{ type: 'composerFocused' }, at(before)],
        [{ type: 'viewportResized' }, at(opening)],
        [
          { type: 'viewportScrolled' },
          at({ ...opening, visual: { ...opening.visual, offsetTop: 150 } }),
        ],
        [{ type: 'viewportScrolled' }, at(rested)],
      ]);
      expect(liftAmounts(commands).every((by) => by === 0)).toBe(true);
      const drag = run(
        run(opened().state, [
          [{ type: 'composerFocused' }, at(before)],
          [{ type: 'viewportResized' }, at(opening)],
          [{ type: 'viewportScrolled' }, at(rested)],
        ]).state,
        [
          [{ type: 'userIntent', touch: true }],
          [{ type: 'viewportScrolled' }, at(dragged)],
        ],
      );
      expect(liftAmounts(drag.commands).at(-1)).toBeCloseTo(lift);
    });
  }

  it('35 iOS still raises at once, as its innerHeight grows under the visual viewport', () => {
    const at = (viewport: typeof device.se2Keyboard.viewport) => ({
      viewport,
      height: viewport.visual.height,
      composerFocused: true,
    });
    const { commands } = run(opened().state, [
      [
        { type: 'composerFocused' },
        at({
          innerHeight: 549,
          rootClientHeight: 549,
          visual: { height: 549, offsetTop: 0, scale: 1 },
        }),
      ],
      [{ type: 'viewportResized' }, at(device.se2Keyboard.viewport)],
      [{ type: 'viewportScrolled' }, at(device.se2KeyboardDrag1.viewport)],
    ]);
    expect(liftAmounts(commands)).toEqual([0, 0, 80]);
  });

  const keyboardQuote = () =>
    run(keyboardOpen(opened().state).state, [
      [{ type: 'quoteClicked', id: 'm4' }],
      [{ type: 'targetLoaded', id: 'm4' }],
      [
        { type: 'targetScrolled', id: 'm4', movedUp: false, moved: false },
        { distance: 78.3, composerFocused: true, height: 420.7 },
      ],
      [{ type: 'composerBlurred' }],
    ]);

  it('36 an original already shown, tapped with the keyboard open, follows again as the keyboard goes', () => {
    const landed = keyboardQuote();
    expect(landed.state.following).toBe(false);
    const { state, commands } = run(landed.state, [
      [{ type: 'viewportResized' }, { height: 744.7, distance: 1 }],
      [{ type: 'newestShown', screen: 'A:', mine: false }],
    ]);
    expect(state.following).toBe(true);
    expect(reads(commands)).toContainEqual({ type: 'read', kind: 'return' });
    expect(scrolls(commands).at(-1)).toEqual({ type: 'alignEnd' });
  });

  it('36 the same when the keyboard is noticed gone only after the jump settled', () => {
    const landed = keyboardQuote();
    const { state } = run(landed.state, [
      [{ type: 'timer', name: 'ownJumpEnd' }],
      [
        { type: 'timer', name: 'keyboardClose' },
        { height: 744.7, distance: 1 },
      ],
    ]);
    expect(state.following).toBe(true);
  });

  it('36 a far original tapped with the keyboard open stays away when it goes', () => {
    const { state } = run(keyboardOpen(opened().state).state, [
      [{ type: 'quoteClicked', id: 'm1' }],
      [{ type: 'targetLoaded', id: 'm1' }],
      [
        { type: 'targetScrolled', id: 'm1', movedUp: true, moved: true },
        { distance: 1500, composerFocused: true, height: 287 },
      ],
      [{ type: 'composerBlurred' }],
      [{ type: 'viewportResized' }, { height: 549, distance: 1500 }],
      [
        { type: 'timer', name: 'keyboardClose' },
        { height: 549, distance: 1500 },
      ],
    ]);
    expect(state.following).toBe(false);
  });

  it('37 a real shrink right after a reveal is answered; a pixel or two is Safari answering the reveal', () => {
    const { state } = keyboardOpen(opened().state);
    const revealed = run(state, [
      [
        { type: 'newestShown', screen: 'A:', mine: false },
        { height: 287, composerFocused: true, reveal: 93 },
      ],
    ]).state;
    const real = run(revealed, [
      [
        { type: 'viewportResized' },
        { height: 247, composerFocused: true, reveal: 40 },
      ],
    ]);
    expect(scrolls(real.commands)).toEqual([{ type: 'reveal', by: 40 }]);
    const echoed = run(revealed, [
      [
        { type: 'viewportResized' },
        { height: 286, composerFocused: true, reveal: 1.4 },
      ],
      [
        { type: 'viewportResized' },
        { height: 285, composerFocused: true, reveal: 1.4 },
      ],
    ]);
    expect(scrolls(echoed.commands)).toEqual([]);
  });

  it('38 a finger resting on the screen after a drag is not pulled by an arriving message', () => {
    const resting = run(opened().state, [
      [{ type: 'touch', down: true }],
      [{ type: 'userIntent', touch: true }],
      [{ type: 'scrolled' }, { distance: 85 }],
      [{ type: 'timer', name: 'userScrollEnd' }, { distance: 85 }],
      [{ type: 'newestShown', screen: 'A:', mine: false }],
    ]);
    expect(scrolls(resting.commands)).toEqual([]);
    expect(resting.state.pendingFollow).toBe(true);
    const lifted = run(resting.state, [
      [{ type: 'touch', down: false }, { distance: 85 }],
      [{ type: 'timer', name: 'userScrollEnd' }, { distance: 85 }],
    ]);
    expect(scrolls(lifted.commands)).toEqual([{ type: 'alignEnd' }]);
  });

  it('38 a tap without a drag lets a message that came in meanwhile be shown as the finger lifts', () => {
    const { commands } = run(opened().state, [
      [{ type: 'touch', down: true }],
      [{ type: 'newestShown', screen: 'A:', mine: false }],
      [{ type: 'touch', down: false }],
    ]);
    expect(scrolls(commands)).toEqual([{ type: 'alignEnd' }]);
  });

  it('38 a lost touchend does not hold following back for good', () => {
    const { state, commands } = run(opened().state, [
      [{ type: 'touch', down: true }],
      [{ type: 'newestShown', screen: 'A:', mine: false }],
      [{ type: 'timer', name: 'touchStale' }],
    ]);
    expect(state.touching).toBe(false);
    expect(scrolls(commands)).toEqual([{ type: 'alignEnd' }]);
  });

  it('39 older messages coming in above keep the reader’s place (review f35f D2: +3,050px)', () => {
    const away = run(opened().state, [
      [{ type: 'scrolled' }, { distance: 3000 }],
    ]).state;
    const { state, commands } = run(away, [
      [{ type: 'olderArriving' }, { firstMessage: { id: 'm40', top: 159 } }],
      [{ type: 'olderLoaded' }, { messageTop: () => 3209 }],
    ]);
    expect(commands).toEqual([{ type: 'scrollBy', by: 3050 }]);
    expect(state.anchor).toBeNull();
  });

  it('39 nothing is moved when the browser kept the place, the anchor is gone, or the reader follows', () => {
    const away = run(opened().state, [
      [{ type: 'scrolled' }, { distance: 3000 }],
    ]).state;
    for (const top of [159, null]) {
      const { commands } = run(away, [
        [{ type: 'olderArriving' }, { firstMessage: { id: 'm40', top: 159 } }],
        [{ type: 'olderLoaded' }, { messageTop: () => top }],
      ]);
      expect(commands).toEqual([]);
    }
    const following = run(opened().state, [
      [{ type: 'olderArriving' }, { firstMessage: { id: 'm40', top: 159 } }],
      [{ type: 'olderLoaded' }, { messageTop: () => 3209 }],
    ]);
    expect(scrolls(following.commands)).toEqual([]);
  });
});

describe('Raising over the iOS keyboard after reading a little up (iPhone on f35f1ec)', () => {
  for (const [name, innerHeight, height, offsetTop, rootClientHeight, was] of [
    ['SE 3, 116~136pt up', 385, 320.5, 226.5, 547, 64.5],
    ['SE 3, 116pt up', 365, 320.5, 226.5, 547, 44.5],
    ['SE 2, 116pt up', 349, 287, 262, 549, 62],
    ['SE 2, 190pt up', 423, 287, 262, 549, 136],
    ['SE 2, 272pt up', 505, 287, 262, 549, 218],
  ] as const) {
    it(`40 raises nothing when Safari already shows the composer on the bottom (${name}, was ${was})`, () => {
      const viewport = {
        innerHeight,
        rootClientHeight,
        visual: { height, offsetTop, scale: 1 },
      };
      expect(keyboardLift(viewport, false)).toBe(0);
      expect(keyboardLift(viewport, true)).toBe(0);
    });
  }

  it('40 still raises by what Safari adds below while the reader drags up (SE 3: 348, 376, 398)', () => {
    for (const [innerHeight, offsetTop, lift] of [
      [348, 199, 27.5],
      [376, 171, 55.5],
      [398, 149.5, 77],
    ] as const)
      expect(
        keyboardLift(
          {
            innerHeight,
            rootClientHeight: 547,
            visual: { height: 320.5, offsetTop, scale: 1 },
          },
          false,
        ),
      ).toBeCloseTo(lift);
  });
});

const iphone = {
  se2BeforeFlick: {
    innerHeight: 447,
    rootClientHeight: 549,
    scrollY: 1797,
    visual: { height: 287, offsetTop: 102, scale: 1, pageTop: 1797 },
  },
  se2Flicked: {
    innerHeight: 549,
    rootClientHeight: 549,
    scrollY: 1611,
    visual: { height: 287, offsetTop: -0.5, scale: 1, pageTop: 1610.5 },
  },
  se3BeforeFlick: {
    innerHeight: 453,
    rootClientHeight: 547,
    scrollY: 1709,
    visual: { height: 320.5, offsetTop: 94, scale: 1, pageTop: 1709 },
  },
  se3Flicked: {
    innerHeight: 547,
    rootClientHeight: 547,
    scrollY: 1567,
    visual: { height: 320.5, offsetTop: 0, scale: 1, pageTop: 1566.5 },
  },
  se2FarFocused: {
    viewport: {
      innerHeight: 549,
      rootClientHeight: 549,
      scrollY: 1938,
      visual: { height: 287, offsetTop: 262, scale: 1, pageTop: 1937.5 },
    },
    scroller: null,
    navigation: { top: 231.5, bottom: 286.5, height: 55 },
    composer: { top: 162.5, bottom: 231.5 },
    end: { top: 634.6, bottom: 634.6 },
  },
  se2FarDragged: {
    viewport: {
      innerHeight: 549,
      rootClientHeight: 549,
      scrollY: 1888,
      visual: { height: 287, offsetTop: 212, scale: 1, pageTop: 1887.5 },
    },
    scroller: null,
    navigation: { top: 231.5, bottom: 286.5, height: 55 },
    composer: { top: 162.5, bottom: 231.5 },
    end: { top: 684.6, bottom: 684.6 },
  },
  se3FarFocused: {
    viewport: {
      innerHeight: 547,
      rootClientHeight: 547,
      scrollY: 1674,
      visual: { height: 320.5, offsetTop: 226.5, scale: 1, pageTop: 1674 },
    },
    scroller: null,
    navigation: { top: 265.5, bottom: 320.5, height: 55 },
    composer: { top: 196.5, bottom: 265.5 },
    end: { top: 648, bottom: 648 },
  },
  se3FarDragged: {
    viewport: {
      innerHeight: 547,
      rootClientHeight: 547,
      scrollY: 1628,
      visual: { height: 320.5, offsetTop: 180, scale: 1, pageTop: 1627.5 },
    },
    scroller: null,
    navigation: { top: 265, bottom: 320, height: 55 },
    composer: { top: 196, bottom: 265 },
    end: { top: 694, bottom: 694 },
  },
  se3AlmostUnzoomed: {
    viewport: {
      innerHeight: 625,
      rootClientHeight: 547,
      scrollY: 1450,
      visual: {
        height: 625,
        offsetTop: 0.5,
        scale: 1.003308653831482,
        pageTop: 1450,
      },
    },
    scroller: null,
    navigation: { top: 569, bottom: 624, height: 55 },
    composer: { top: 500, bottom: 569 },
    end: { top: 570, bottom: 570 },
  },
  se2QuoteShown: {
    viewport: {
      innerHeight: 549,
      rootClientHeight: 549,
      scrollY: 1825,
      visual: { height: 549, offsetTop: 0, scale: 1, pageTop: 1825 },
    },
    scroller: null,
    navigation: { top: 494, bottom: 549, height: 55 },
    composer: { top: 425, bottom: 494 },
    end: { top: 494.8, bottom: 494.8 },
  },
  se2QuoteShownKeyboard: {
    viewport: {
      innerHeight: 287,
      rootClientHeight: 549,
      scrollY: 2119,
      visual: { height: 287, offsetTop: 262, scale: 1, pageTop: 2119 },
    },
    scroller: null,
    navigation: { top: 232, bottom: 287, height: 55 },
    composer: { top: 163, bottom: 232 },
    end: { top: 232.8, bottom: 232.8 },
  },
} satisfies Record<string, LayoutReading | LayoutReading['viewport']>;

describe('iPhone on ddbad17ba3 (ios-masto-final3)', () => {
  const at = (viewport: LayoutReading['viewport'], over = {}) => ({
    viewport,
    height: viewport.visual?.height ?? viewport.innerHeight,
    composerFocused: true,
    ...over,
  });

  for (const [name, base, keyboard, dragged, before, flicked, lift] of [
    [
      'SE 2',
      549,
      { ...device.se2Keyboard.viewport, scrollY: 1957 },
      device.se2KeyboardDrag1.viewport,
      iphone.se2BeforeFlick,
      iphone.se2Flicked,
      262.5,
    ],
    [
      'SE 3',
      547,
      { ...device.se3Keyboard.viewport, scrollY: 1842 },
      {
        innerHeight: 398,
        rootClientHeight: 547,
        visual: { height: 320.5, offsetTop: 149.5, scale: 1 },
      },
      iphone.se3BeforeFlick,
      iphone.se3Flicked,
      226.5,
    ],
  ] as const) {
    it(`41 a flick with the keyboard open keeps the composer over the keyboard (${name}: 0 on ddbad17, ${lift})`, () => {
      const start: LayoutReading['viewport'] = {
        innerHeight: base,
        rootClientHeight: base,
        visual: { height: base, offsetTop: 0, scale: 1 },
      };
      const { commands } = run(opened().state, [
        [{ type: 'composerFocused' }, at(start)],
        [{ type: 'viewportResized' }, at(keyboard)],
        [{ type: 'userIntent', touch: true }],
        [{ type: 'viewportScrolled' }, at(dragged)],
        [{ type: 'viewportScrolled' }, at(before)],
        [{ type: 'touch', down: false }],
        [{ type: 'viewportScrolled' }, at(flicked)],
        [{ type: 'viewportResized' }, at(flicked)],
      ]);
      expect(liftAmounts(commands).at(-1)).toBeCloseTo(lift);
    });
  }

  it('41 an Android keyboard still opening is not taken for that flick', () => {
    const { commands } = run(opened().state, [
      [{ type: 'composerFocused' }, at(device.galaxy.viewport)],
      [{ type: 'viewportResized' }, at(galaxyOpening)],
    ]);
    expect(liftAmounts(commands).every((by) => by === 0)).toBe(true);
  });

  it('42 Safari’s visual viewport offset is not added when scrollY already is its top (far focus: 85.6/101 on ddbad17)', () => {
    expect(visibleArea(iphone.se2FarFocused.viewport)).toMatchObject({
      top: 0,
      bottom: 287,
    });
    expect(distanceFromNewest(iphone.se2FarFocused)).toBeCloseTo(403.1);
    expect(distanceFromNewest(iphone.se3FarFocused)).toBeCloseTo(382.5);
    expect(distanceFromNewest(iphone.se2FarDragged)).toBeCloseTo(453.1);
    expect(distanceFromNewest(iphone.se3FarDragged)).toBeCloseTo(429);
    expect(
      visibleArea({
        ...device.galaxyKeyboard.viewport,
        scrollY: 1275.3,
        visual: { ...device.galaxyKeyboard.viewport.visual, pageTop: 1599.3 },
      }).top,
    ).toBe(324);
  });

  it('42 reading a little with the keyboard open far up does not start following, nor pull to a new message', () => {
    for (const [focused, dragged] of [
      [iphone.se2FarFocused, iphone.se2FarDragged],
      [iphone.se3FarFocused, iphone.se3FarDragged],
    ] as const) {
      const away = run(opened().state, [
        [{ type: 'scrolled' }, { distance: 457.6 }],
      ]).state;
      const { state, commands } = run(away, [
        [
          { type: 'composerFocused' },
          {
            composerFocused: true,
            height: focused.viewport.innerHeight,
            distance: 457.6,
          },
        ],
        [
          { type: 'viewportResized' },
          at(focused.viewport, { distance: distanceFromNewest(focused) }),
        ],
        [{ type: 'userIntent', touch: true }],
        [
          { type: 'viewportScrolled' },
          at(dragged.viewport, { distance: distanceFromNewest(dragged) }),
        ],
        [
          { type: 'scrolled' },
          at(dragged.viewport, { distance: distanceFromNewest(dragged) }),
        ],
        [{ type: 'touch', down: false }],
        [{ type: 'timer', name: 'userScrollEnd' }],
        [
          { type: 'newestShown', screen: 'A:', mine: false },
          at(focused.viewport, { distance: 500, reveal: 176 }),
        ],
      ]);
      expect(state.following).toBe(false);
      expect(scrolls(commands)).toEqual([]);
    }
  });

  for (const [name, distance, reveal] of [
    ['SE 2, 117pt up', 117.1, 116],
    ['SE 3, 87pt up', 86.9, 85],
  ] as const)
    it(`43 focusing the box near the newest shows it before the keyboard opens (${name})`, () => {
      const near = run(opened().state, [
        [{ type: 'scrolled' }, { distance }],
      ]).state;
      expect(near.following).toBe(true);
      const { commands } = run(near, [
        [
          { type: 'composerFocused' },
          { composerFocused: true, height: 549, distance, reveal },
        ],
      ]);
      expect(scrolls(commands)).toEqual([{ type: 'reveal', by: reveal }]);
    });

  it('43 focusing the box at the newest, or away from it, moves nothing', () => {
    for (const distance of [1.1, 300]) {
      const state = run(opened().state, [
        [{ type: 'scrolled' }, { distance }],
      ]).state;
      const { commands } = run(state, [
        [
          { type: 'composerFocused' },
          { composerFocused: true, height: 549, distance, reveal: 50 },
        ],
      ]);
      expect(scrolls(commands)).toEqual([]);
    }
  });

  const forgets = (commands: Command[]) =>
    commands.filter((command) => command.type === 'forgetSearch').length;

  it('44 a room opened at a searched message forgets it once it is reached', () => {
    const { commands } = run(opened('m1').state, [
      [{ type: 'targetLoaded', id: 'm1' }],
      [
        { type: 'targetScrolled', id: 'm1', movedUp: true, moved: true },
        { distance: 5482 },
      ],
      [{ type: 'timer', name: 'highlightEnd' }],
      [{ type: 'jumpToNewest' }],
    ]);
    expect(forgets(commands)).toBe(1);
  });

  it('44 or once the reader goes to the newest before it is reached', () => {
    for (const toNewest of [
      [{ type: 'jumpToNewest' }, {}],
      [{ type: 'targetMissing' }, {}],
    ] as [ScrollEvent, Partial<Snapshot>][]) {
      const { commands } = run(opened('m1').state, [toNewest]);
      expect(forgets(commands)).toBe(1);
    }
    const scrolled = run(opened('m1').state, [
      [{ type: 'userIntent', touch: true }],
      [{ type: 'scrolled' }, { distance: 3000 }],
      [{ type: 'scrolled' }, { distance: 100 }],
    ]);
    expect(forgets(scrolled.commands)).toBe(1);
  });

  it('44 a quote, or a room opened without a searched message, has nothing to forget', () => {
    const { commands } = run(opened().state, [
      [{ type: 'quoteClicked', id: 'm4' }],
      [{ type: 'targetLoaded', id: 'm4' }],
      [
        { type: 'targetScrolled', id: 'm4', movedUp: true, moved: true },
        { distance: 400 },
      ],
      [{ type: 'jumpToNewest' }],
    ]);
    expect(forgets(commands)).toBe(0);
  });

  it('45 an original in full view is where it is: on the screen, clear of the composer', () => {
    expect(rectShown(iphone.se2QuoteShown, { top: 274.1, bottom: 308.9 })).toBe(
      true,
    );
    expect(rectShown(iphone.se2QuoteShown, { top: 400, bottom: 440 })).toBe(
      false,
    );
    expect(
      rectShown(iphone.se2QuoteShownKeyboard, { top: 12.1, bottom: 46.9 }),
    ).toBe(true);
    expect(
      rectShown(iphone.se2QuoteShownKeyboard, { top: -20, bottom: 20 }),
    ).toBe(false);
  });

  it('45 a quote whose original is in full view highlights it without moving, following or not (63px on ddbad17)', () => {
    for (const distance of [0.8, 150, 600]) {
      const before = run(opened().state, [
        [{ type: 'scrolled' }, { distance }],
      ]).state;
      const { state, commands } = run(before, [
        [
          { type: 'quoteClicked', id: 'm4' },
          { messageShown: (id) => id === 'm4', distance },
        ],
        [{ type: 'targetLoaded', id: 'm4' }, { distance }],
      ]);
      expect(scrolls(commands)).toEqual([]);
      expect(state.following).toBe(before.following);
      expect(state.target).toMatchObject({ id: 'm4', phase: 'landed' });
      expect(commands).toContainEqual({
        type: 'timer',
        name: 'highlightEnd',
        delay: 3000,
      });
      expect(commands.some((command) => command.type === 'away')).toBe(false);
    }
  });

  it('45 with the keyboard open it keeps following as the quote takes the focus and the keyboard goes', () => {
    const { state, commands } = run(keyboardOpen(opened().state).state, [
      [{ type: 'pageAction' }],
      [
        { type: 'quoteClicked', id: 'm4' },
        { messageShown: () => true, composerFocused: true, height: 287 },
      ],
      [{ type: 'composerBlurred' }],
      [
        { type: 'timer', name: 'keyboardClose' },
        { height: 549, distance: 1 },
      ],
    ]);
    expect(state.following).toBe(true);
    expect(scrolls(commands).filter((c) => c.type !== 'alignEnd')).toEqual([]);
  });

  it('46 a scale within 0.01 of 1 is not zoomed in (SE 3: 1.0033 after letting go of a pinch)', () => {
    expect(visibleArea(iphone.se3AlmostUnzoomed.viewport).scale).toBe(1);
    expect(
      visibleArea({
        ...iphone.se3AlmostUnzoomed.viewport,
        visual: { height: 520, offsetTop: 0, scale: 1.045 },
      }).scale,
    ).toBe(1.045);
    expect(
      rectVisible(iphone.se3AlmostUnzoomed, { top: 440, bottom: 495 }),
    ).toBe(true);
    const scale = visibleArea(iphone.se3AlmostUnzoomed.viewport).scale;
    const { state, commands } = run(opened().state, [
      [{ type: 'viewportResized' }, { scale: 1.72 }],
      [{ type: 'scrolled' }, { scale: 1.72 }],
      [
        { type: 'viewportResized' },
        { scale, distance: distanceFromNewest(iphone.se3AlmostUnzoomed) },
      ],
    ]);
    expect(state.following).toBe(true);
    expect(reads(commands)).toContainEqual({ type: 'read', kind: 'return' });
  });
});

describe('Android on a7566004ab (android-masto-final4)', () => {
  const unzoomed = {
    galaxy: {
      viewport: {
        innerHeight: 744,
        rootClientHeight: 744,
        scrollY: 1344,
        visual: { height: 741, offsetTop: 3.6, scale: 1.005, pageTop: 1347.7 },
      },
      scroller: null,
      navigation: { top: 689.7, bottom: 744.7, height: 55 },
      composer: { top: 620.7, bottom: 689.7 },
      end: { top: 732, bottom: 732 },
    },
    pixel: {
      viewport: {
        innerHeight: 603,
        rootClientHeight: 603,
        scrollY: 1437.7,
        visual: {
          height: 600.5,
          offsetTop: 2.7,
          scale: 1.005,
          pageTop: 1440.4,
        },
      },
      scroller: null,
      navigation: { top: 548.9, bottom: 603.4, height: 54.5 },
      composer: { top: 479.7, bottom: 548.4 },
      end: { top: 570.6, bottom: 570.6 },
    },
  } satisfies Record<string, LayoutReading>;

  for (const [name, layout, distance] of [
    ['Galaxy', unzoomed.galaxy, 42.3],
    ['Pixel', unzoomed.pixel, 21.7],
  ] as const)
    it(`47 letting go of a pinch at 1.005 near the newest follows and reads again (${name}, ${distance}px)`, () => {
      expect(distanceFromNewest(layout)).toBeCloseTo(distance);
      const scale = visibleArea(layout.viewport).scale;
      expect(scale).toBe(1);
      const unzoom = run(opened().state, [
        [{ type: 'viewportResized' }, { scale: 1.795 }],
        [{ type: 'scrolled' }, { scale: 1.795 }],
        [{ type: 'viewportScrolled' }, { scale: 1.795 }],
        [
          { type: 'viewportResized' },
          { scale, distance: distanceFromNewest(layout) },
        ],
      ]);
      expect(unzoom.state.following).toBe(true);
      expect(lastAway(unzoom.commands)).toBe(false);
      expect(reads(unzoom.commands)).toContainEqual({
        type: 'read',
        kind: 'return',
      });
      const arrival = run(unzoom.state, [
        [{ type: 'newestShown', screen: 'A:', mine: false }, { scale }],
      ]);
      expect(scrolls(arrival.commands)).toEqual([{ type: 'alignEnd' }]);
    });

  it('47 letting go of a pinch away from the newest still keeps the place (300px)', () => {
    const { state } = run(opened().state, [
      [{ type: 'viewportResized' }, { scale: 1.795 }],
      [{ type: 'scrolled' }, { scale: 1.795 }],
      [{ type: 'viewportResized' }, { scale: 1, distance: 300 }],
    ]);
    expect(state.following).toBe(false);
  });
});

describe('iPhone SE 3 on a7566004ab (ios-masto-final4)', () => {
  const se3 = (
    innerHeight: number,
    height: number,
    offsetTop: number,
    scrollY: number,
  ) => ({
    innerHeight,
    rootClientHeight: 547,
    scrollY,
    visual: { height, offsetTop, scale: 1, pageTop: scrollY },
  });
  const at = (
    viewport: ReturnType<typeof se3>,
    over: Partial<Snapshot> = {},
  ) => ({
    viewport,
    height: viewport.visual.height,
    composerFocused: true,
    ...over,
  });
  const rooms = (commands: Command[]) =>
    commands
      .filter(
        (command): command is Extract<Command, { type: 'room' }> =>
          command.type === 'room',
      )
      .map((command) => command.by);

  it('48 measures how far Safari leaves the end of the page under the keyboard', () => {
    expect(keyboardRoom(se3(367, 320.5, 226.5, 1725))).toBeCloseTo(46.5);
    expect(keyboardRoom(se3(414, 320.5, 226.5, 1634))).toBeCloseTo(93.5);
    expect(keyboardRoom(se3(321, 320.5, 226.5, 1842))).toBe(0);
    expect(keyboardRoom(se3(398, 320.5, 149.5, 1765))).toBe(0);
    expect(
      keyboardRoom({ ...device.se2Keyboard.viewport, scrollY: 1957 }),
    ).toBe(0);
    expect(keyboardRoom(device.galaxyKeyboard.viewport)).toBe(0);
  });

  for (const [name, before, distance, safari, room, last] of [
    ['a130, 119pt up', 1427, 119, se3(367, 320.5, 226.5, 1725), 46.5, 228],
    ['ak180, 165pt up', 1336, 165, se3(414, 320.5, 226.5, 1634), 93.5, 275],
  ] as const)
    it(`48 the newest is shown over the keyboard although Safari scrolled from where the page was (${name})`, () => {
      const near = run(opened().state, [
        [{ type: 'scrolled' }, { distance }],
      ]).state;
      const opening = run(near, [
        [
          { type: 'composerFocused' },
          at(se3(547, 547, 0, before), { distance, reveal: distance - 1 }),
        ],
        [
          { type: 'viewportResized' },
          at(se3(547, 320.5, 0, before + distance - 1)),
        ],
        [{ type: 'viewportScrolled' }, at(safari)],
        [{ type: 'viewportResized' }, at(safari)],
      ]);
      expect(rooms(opening.commands)).toEqual([room]);
      const reveal = Math.min(last - 196.5 + 16, room);
      const made = run(opening.state, [
        [{ type: 'roomMade' }, at(safari, { remaining: room, reveal })],
      ]);
      expect(scrolls(made.commands)).toEqual([{ type: 'reveal', by: reveal }]);
      const closed = run(made.state, [
        [{ type: 'composerBlurred' }],
        [{ type: 'timer', name: 'keyboardClose' }, { distance: 1 }],
      ]);
      expect(closed.commands.map((command) => command.type)).toEqual(
        expect.arrayContaining(['room', 'alignEnd']),
      );
      expect(rooms(closed.commands)).toEqual([null]);
      const order = closed.commands.map((command) => command.type);
      expect(order.indexOf('room')).toBeLessThan(order.indexOf('alignEnd'));
    });

  it('48 a reader away from the newest, or a page not at its end, is given no room', () => {
    const away = run(opened().state, [
      [{ type: 'scrolled' }, { distance: 300 }],
    ]).state;
    const { commands } = run(away, [
      [{ type: 'composerFocused' }, at(se3(547, 547, 0, 1285))],
      [{ type: 'viewportScrolled' }, at(se3(509, 320.5, 226.5, 1583))],
    ]);
    expect(rooms(commands)).toEqual([]);
    const following = run(opened().state, [
      [{ type: 'composerFocused' }, at(se3(547, 547, 0, 1938))],
      [
        { type: 'viewportScrolled' },
        at(
          {
            innerHeight: 549,
            rootClientHeight: 549,
            scrollY: 1938,
            visual: { height: 287, offsetTop: 262, scale: 1, pageTop: 1937.5 },
          },
          { remaining: 140 },
        ),
      ],
    ]);
    expect(rooms(following.commands)).toEqual([]);
  });
});

describe('Review 730b E1: focusing the box at the newest with the browser bar collapsed', () => {
  const collapsed = [
    [
      'Pixel URL bar (kcol-1)',
      {
        innerHeight: 659,
        rootClientHeight: 603,
        scrollY: 1266.7,
        visual: { height: 659.4, offsetTop: 0, scale: 1, pageTop: 1266.7 },
      },
      0.3,
      0.8,
    ],
    [
      'SE 2 toolbar (b-c11)',
      {
        innerHeight: 589,
        rootClientHeight: 549,
        scrollY: 1648,
        visual: { height: 589, offsetTop: 0, scale: 1, pageTop: 1648 },
      },
      0,
      0.6,
    ],
    [
      'SE 3 toolbar (b-c11)',
      {
        innerHeight: 625,
        rootClientHeight: 547,
        scrollY: 1496,
        visual: { height: 625, offsetTop: 1, scale: 1, pageTop: 1496 },
      },
      -1,
      1.5,
    ],
  ] as const;
  const rooms = (commands: Command[]) =>
    commands
      .filter(
        (command): command is Extract<Command, { type: 'room' }> =>
          command.type === 'room',
      )
      .map((command) => command.by);
  const at = (
    viewport: Snapshot['viewport'],
    over: Partial<Snapshot> = {},
  ): Partial<Snapshot> => ({
    viewport,
    height: viewport.visual?.height ?? viewport.innerHeight,
    composerFocused: true,
    ...over,
  });

  it('49 nothing is left under a keyboard before one is shown (Pixel 56, SE 2 40, SE 3 79 on 730b)', () => {
    for (const [, viewport] of collapsed)
      expect(keyboardRoom(viewport)).toBe(0);
  });

  for (const [name, viewport, remaining, distance] of collapsed)
    it(`49 no room is made at the focus (${name})`, () => {
      const { state, commands } = run(opened().state, [
        [{ type: 'composerFocused' }, at(viewport, { remaining, distance })],
      ]);
      expect(rooms(commands)).toEqual([]);
      expect(state.keyboard?.room).toBe(0);
    });

  it('49 nor as Chrome opens its keyboard over the collapsed bar (kcol-1: 351.7, 375.2 at 4.2, 99.8, 284.2)', () => {
    const [, focus, remaining, distance] = collapsed[0];
    const chrome = (height: number, offsetTop: number) => ({
      innerHeight: 659,
      rootClientHeight: 659,
      scrollY: 1266.7,
      visual: {
        height,
        offsetTop,
        scale: 1,
        pageTop: 1266.7 + offsetTop,
      },
    });
    const { state, commands } = run(opened().state, [
      [{ type: 'composerFocused' }, at(focus, { remaining, distance })],
      [{ type: 'viewportResized' }, at(chrome(351.7, 0), { remaining })],
      [{ type: 'viewportScrolled' }, at(chrome(375.2, 4.2), { remaining })],
      [{ type: 'viewportScrolled' }, at(chrome(375.2, 99.8), { remaining })],
      [{ type: 'viewportScrolled' }, at(chrome(375.2, 284.2), { remaining })],
    ]);
    expect(rooms(commands)).toEqual([]);
    expect(liftAmounts(commands).every((by) => by === 0 || by === null)).toBe(
      true,
    );
    expect(state.keyboard?.rested).toBe(true);
  });

  for (const [name, focus, keyboard] of [
    [
      'SE 2',
      collapsed[1],
      {
        innerHeight: 287,
        rootClientHeight: 549,
        scrollY: 1910,
        visual: { height: 287, offsetTop: 262, scale: 1, pageTop: 1910 },
      },
    ],
    [
      'SE 3',
      collapsed[2],
      {
        innerHeight: 321,
        rootClientHeight: 547,
        scrollY: 1795,
        visual: { height: 320.5, offsetTop: 226.5, scale: 1, pageTop: 1795 },
      },
    ],
  ] as const)
    it(`49 nor once Safari's keyboard is shown at the newest (${name})`, () => {
      const [, viewport, remaining, distance] = focus;
      const { commands } = run(opened().state, [
        [{ type: 'composerFocused' }, at(viewport, { remaining, distance })],
        [{ type: 'viewportResized' }, at(keyboard, { remaining: 0 })],
        [{ type: 'viewportScrolled' }, at(keyboard, { remaining: 0 })],
      ]);
      expect(rooms(commands)).toEqual([]);
    });

  it('49 the room Safari 18 leaves is still made once in the session, after a focus that left nothing (a130)', () => {
    const [, viewport, remaining, distance] = collapsed[2];
    const safari = {
      innerHeight: 367,
      rootClientHeight: 547,
      scrollY: 1725,
      visual: { height: 320.5, offsetTop: 226.5, scale: 1, pageTop: 1725 },
    };
    const { commands } = run(opened().state, [
      [{ type: 'composerFocused' }, at(viewport, { remaining, distance })],
      [{ type: 'viewportScrolled' }, at(safari, { remaining: 0 })],
      [{ type: 'viewportResized' }, at(safari, { remaining: 0 })],
    ]);
    expect(rooms(commands)).toEqual([46.5]);
  });
});

describe('Review 730b J1: a quote highlighted where it is keeps the place to go back to', () => {
  const restores = (commands: Command[]) =>
    commands.filter((command) => command.type === 'restoreScroll');
  const readUpWithKeyboard = () =>
    run(keyboardOpen(opened().state).state, [
      [
        { type: 'touch', down: true },
        { composerFocused: true, height: 287 },
      ],
      [
        { type: 'userIntent', touch: true },
        { composerFocused: true, height: 287 },
      ],
      [
        { type: 'scrolled' },
        { composerFocused: true, height: 287, distance: 300, scrollTop: 3201 },
      ],
      [
        { type: 'touch', down: false },
        { composerFocused: true, height: 287 },
      ],
      [
        { type: 'timer', name: 'userScrollEnd' },
        { composerFocused: true, height: 287, distance: 300, scrollTop: 3201 },
      ],
    ]).state;
  const focusedAway = () => {
    const away = run(opened().state, [
      [{ type: 'scrolled' }, { distance: 418, scrollTop: 1128 }],
    ]).state;
    return run(away, [
      [
        { type: 'composerFocused' },
        { height: 547, scrollTop: 1128, composerFocused: true, distance: 418 },
      ],
      [
        { type: 'viewportResized' },
        {
          height: 320.5,
          scrollTop: 1426,
          composerFocused: true,
          distance: 346.5,
        },
      ],
      [
        { type: 'scrolled' },
        {
          height: 320.5,
          scrollTop: 1426,
          composerFocused: true,
          distance: 346.5,
        },
      ],
    ]).state;
  };
  const tapShownQuote = (state: ScrollState) =>
    run(state, [
      [
        { type: 'pageAction', quote: 'm4' },
        { composerFocused: true, messageShown: (id) => id === 'm4' },
      ],
      [{ type: 'composerBlurred' }],
      [
        { type: 'quoteClicked', id: 'm4' },
        { messageShown: (id) => id === 'm4' },
      ],
    ]);
  const close = (state: ScrollState, distance: number) =>
    run(state, [[{ type: 'timer', name: 'keyboardClose' }, { distance }]]);

  for (const [name, reading, top, distance] of [
    [
      'read up with the keyboard open (review probe)',
      readUpWithKeyboard,
      3201,
      300,
    ],
    ['read up, then focused (SE 3 b-aw1)', focusedAway, 1128, 418],
  ] as const) {
    it(`J1 control: closing goes back to ${top} (${name})`, () => {
      const closed = run(reading(), [[{ type: 'composerBlurred' }]]);
      expect(restores(close(closed.state, distance).commands)).toEqual([
        { type: 'restoreScroll', top },
      ]);
    });

    it(`J1 closing after the quote still goes back to ${top} (${name})`, () => {
      const tapped = tapShownQuote(reading());
      expect(scrolls(tapped.commands)).toEqual([]);
      expect(tapped.state.target).toMatchObject({ id: 'm4', phase: 'landed' });
      expect(tapped.state.following).toBe(false);
      expect(restores(close(tapped.state, distance).commands)).toEqual([
        { type: 'restoreScroll', top },
      ]);
    });
  }

  it('J1 a quote to an original out of view still wins over the place (25)', () => {
    const { state } = run(focusedAway(), [
      [
        { type: 'pageAction', quote: 'm1' },
        { composerFocused: true, messageShown: () => false },
      ],
      [{ type: 'quoteClicked', id: 'm1' }, { messageShown: () => false }],
      [{ type: 'targetLoaded', id: 'm1' }],
      [
        { type: 'targetScrolled', id: 'm1', movedUp: true, moved: true },
        { distance: 900 },
      ],
      [{ type: 'composerBlurred' }],
    ]);
    expect(restores(close(state, 900).commands)).toEqual([]);
  });

  it('J1 any other button pressed still cancels going back (25)', () => {
    const { state } = run(focusedAway(), [
      [{ type: 'pageAction' }, { composerFocused: true }],
      [{ type: 'composerBlurred' }],
    ]);
    expect(restores(close(state, 418).commands)).toEqual([]);
  });

  it('J1 after an explicit move, a quote highlighted where it is gives back nothing', () => {
    const { state } = run(focusedAway(), [
      [{ type: 'jumpToNewest' }, { composerFocused: true }],
      [{ type: 'scrolled' }, { distance: 600, scrollTop: 900 }],
      [
        { type: 'pageAction', quote: 'm4' },
        { composerFocused: true, messageShown: () => true },
      ],
      [{ type: 'quoteClicked', id: 'm4' }, { messageShown: () => true }],
      [{ type: 'composerBlurred' }],
    ]);
    expect(restores(close(state, 600).commands)).toEqual([]);
  });
});

describe('Android on f496c2c262 and review f496', () => {
  const restores = (commands: Command[]) =>
    commands.filter((command) => command.type === 'restoreScroll');
  const timers = (commands: Command[], name: string) =>
    commands.filter(
      (command) => command.type === 'timer' && command.name === name,
    );

  const pixelUnderHeader: LayoutReading = {
    viewport: {
      innerHeight: 603,
      rootClientHeight: 603,
      visual: { height: 603.4, offsetTop: 0, scale: 1 },
    },
    scroller: null,
    navigation: { top: 548.9, bottom: 603.4, height: 54.5 },
    composer: { top: 479.7, bottom: 548.4 },
    end: { top: 687.5, bottom: 687.5 },
    header: { top: 0, bottom: 50.8 },
  };
  const pixelOriginal: Box = { top: 31.6, bottom: 66 };
  const underHeader: [string, LayoutReading, Box, Box][] = [
    [
      'Pixel s7h-1',
      pixelUnderHeader,
      pixelOriginal,
      { top: 140.7, bottom: 188.5 },
    ],
    [
      'Galaxy s7h-1',
      {
        viewport: {
          innerHeight: 744,
          rootClientHeight: 744,
          visual: { height: 744.7, offsetTop: 0, scale: 1 },
        },
        scroller: null,
        navigation: { top: 689.7, bottom: 744.7, height: 55 },
        composer: { top: 620.7, bottom: 689.7 },
        end: { top: 690.6, bottom: 690.6 },
        header: { top: 0, bottom: 51 },
      },
      { top: 27.7, bottom: 62.6 },
      { top: 138.3, bottom: 186.3 },
    ],
  ];
  for (const [name, layout, original, quoted] of underHeader) {
    it(`an original partly under the column header is not in full view (${name})`, () => {
      expect(rectShown(layout, original)).toBe(false);
      expect(rectShown(layout, quoted)).toBe(true);
    });

    it(`what the column header covers is not seen (${name})`, () => {
      expect(rectVisible(layout, { top: 0, bottom: 45 })).toBe(false);
      expect(rectVisible(layout, original)).toBe(true);
    });
  }

  it('a column header scrolled away, or above what Chrome shows over its keyboard, covers nothing', () => {
    expect(
      rectShown(
        { ...pixelUnderHeader, header: { top: -60, bottom: -9.2 } },
        pixelOriginal,
      ),
    ).toBe(true);
    expect(
      rectShown(
        { ...device.pixelKeyboard, header: { top: 0, bottom: 50.8 } },
        { top: 300, bottom: 340 },
      ),
    ).toBe(true);
  });

  const pixelUpCollapsed = (state: ScrollState) =>
    run(state, [
      [
        { type: 'scrolled' },
        {
          distance: 273.3,
          scrollTop: 902.1,
          viewport: {
            innerHeight: 659,
            rootClientHeight: 603,
            visual: { height: 659.4, offsetTop: 0, scale: 1 },
          },
        },
      ],
      [
        { type: 'composerFocused' },
        {
          height: 659.4,
          scrollTop: 902.1,
          composerFocused: true,
          distance: 273.3,
          viewport: {
            innerHeight: 659,
            rootClientHeight: 603,
            visual: { height: 659.4, offsetTop: 0, scale: 1 },
          },
        },
      ],
      [
        { type: 'viewportResized' },
        {
          height: 375.2,
          scrollTop: 1033.9,
          composerFocused: true,
          distance: 0.8,
          viewport: {
            innerHeight: 659,
            rootClientHeight: 659,
            visual: { height: 375.2, offsetTop: 284.2, scale: 1 },
          },
        },
      ],
    ]);
  const backKey = (
    state: ScrollState,
    sizes: [number, number, number][],
  ): ReturnType<typeof run> =>
    run(
      state,
      sizes.map(([innerHeight, rootClientHeight, height]) => [
        { type: 'viewportResized' },
        {
          height,
          scrollTop: 1033.9,
          composerFocused: true,
          distance: 233.9,
          viewport: {
            innerHeight,
            rootClientHeight,
            visual: { height, offsetTop: 0, scale: 1 },
          },
        },
      ]),
    );

  it('3 the keyboard put away as Chrome shows its bar again is closed, and the place is given back (kupc-3)', () => {
    const opened3 = pixelUpCollapsed(opened().state);
    expect(opened3.state.keyboard).toMatchObject({
      restoreTop: 902.1,
      following: false,
      shrunk: true,
    });
    const hidden = backKey(opened3.state, [
      [659, 659, 603.4],
      [603, 603, 603.4],
    ]);
    expect(timers(hidden.commands, 'keyboardClose')).toEqual([
      { type: 'timer', name: 'keyboardClose', delay: 200 },
    ]);
    const closed = run(hidden.state, [
      [{ type: 'timer', name: 'keyboardClose' }, { distance: 233.9 }],
    ]);
    expect(restores(closed.commands)).toEqual([
      { type: 'restoreScroll', top: 902.1 },
    ]);
    expect(closed.state.keyboard).toBeNull();
  });

  it('3 control: put away through the collapsed height, as before (kupc-2)', () => {
    const hidden = backKey(pixelUpCollapsed(opened().state).state, [
      [659, 659, 659.4],
      [603, 603, 603.4],
    ]);
    expect(timers(hidden.commands, 'keyboardClose').length).toBeGreaterThan(0);
  });

  it('3 nothing is closed while a keyboard is up, whatever the bar does', () => {
    const { commands } = backKey(pixelUpCollapsed(opened().state).state, [
      [659, 659, 319.2],
      [603, 603, 319.2],
      [603, 603, 375.2],
    ]);
    expect(timers(commands, 'keyboardClose')).toEqual([]);
    const iphone = run(opened().state, [
      [
        { type: 'composerFocused' },
        { height: 547, composerFocused: true, distance: 418 },
      ],
      [
        { type: 'viewportResized' },
        {
          height: 320.5,
          composerFocused: true,
          viewport: {
            innerHeight: 367,
            rootClientHeight: 547,
            visual: { height: 320.5, offsetTop: 226.5, scale: 1 },
          },
        },
      ],
    ]);
    expect(timers(iphone.commands, 'keyboardClose')).toEqual([]);
  });

  it('3 a keyboard that shortens the root with it is still open', () => {
    const page = (height: number) => ({
      height,
      composerFocused: true,
      viewport: {
        innerHeight: height,
        rootClientHeight: height,
        visual: { height, offsetTop: 0, scale: 1 },
      },
    });
    const away = run(opened().state, [
      [{ type: 'scrolled' }, { distance: 600, scrollTop: 2901 }],
    ]).state;
    const open = run(away, [
      [{ type: 'composerFocused' }, { ...page(667), scrollTop: 2901 }],
      [{ type: 'viewportResized' }, page(367)],
      [{ type: 'scrolled' }, { ...page(367), scrollTop: 3321 }],
    ]);
    expect(timers(open.commands, 'keyboardClose')).toEqual([]);
    const closed = run(open.state, [
      [{ type: 'viewportResized' }, page(667)],
      [{ type: 'composerBlurred' }, page(667)],
      [{ type: 'timer', name: 'keyboardClose' }, { distance: 600 }],
    ]);
    expect(restores(closed.commands)).toEqual([
      { type: 'restoreScroll', top: 2901 },
    ]);
  });

  it('5 the navigation bar is on the bottom of what is shown while Chrome hides its bar (kupc-7)', () => {
    const hiding: LayoutReading = {
      viewport: {
        innerHeight: 603,
        rootClientHeight: 603,
        visual: { height: 659.4, offsetTop: 0, scale: 1 },
      },
      scroller: null,
      navigation: { top: 548.9, bottom: 603.4, height: 54.5 },
      composer: { top: 479.7, bottom: 548.4 },
      end: { top: 878.8, bottom: 878.8 },
    };
    const resized: LayoutReading = {
      ...hiding,
      viewport: { ...hiding.viewport, innerHeight: 659 },
      navigation: { top: 604.9, bottom: 659.4, height: 54.5 },
      composer: { top: 535.7, bottom: 604.4 },
      end: { top: 878, bottom: 878 },
    };
    expect(distanceFromNewest(resized)).toBeCloseTo(273.1, 1);
    expect(distanceFromNewest(hiding)).toBeCloseTo(273.9, 1);
    expect(distanceFromNewest(hiding)).toBeGreaterThanOrEqual(240);
  });

  const focusedAway = () => {
    const away = run(opened().state, [
      [{ type: 'scrolled' }, { distance: 418, scrollTop: 1128 }],
    ]).state;
    return run(away, [
      [
        { type: 'composerFocused' },
        { height: 547, scrollTop: 1128, composerFocused: true, distance: 418 },
      ],
      [
        { type: 'viewportResized' },
        {
          height: 320.5,
          scrollTop: 1426,
          composerFocused: true,
          distance: 346.5,
        },
      ],
      [
        { type: 'scrolled' },
        {
          height: 320.5,
          scrollTop: 1426,
          composerFocused: true,
          distance: 346.5,
        },
      ],
    ]).state;
  };
  const close = (state: ScrollState, distance: number) =>
    run(state, [
      [{ type: 'composerBlurred' }],
      [{ type: 'timer', name: 'keyboardClose' }, { distance }],
    ]);
  const moves = (commands: Command[]) =>
    commands.filter((command) =>
      [
        'alignEnd',
        'reveal',
        'scrollToMessage',
        'restoreScroll',
        'scrollBy',
      ].includes(command.type),
    );

  it('J1′ the same quote pressed again while highlighted keeps the place to go back to (SE 3 b-aw1)', () => {
    const first = run(focusedAway(), [
      [
        { type: 'pageAction', quote: 'm4' },
        { composerFocused: true, height: 320.5, messageShown: () => true },
      ],
      [
        { type: 'quoteClicked', id: 'm4' },
        { composerFocused: true, height: 320.5, messageShown: () => true },
      ],
      [{ type: 'contentResized' }, { composerFocused: true, height: 320.5 }],
    ]);
    const again = run(first.state, [
      [
        { type: 'pageAction', quote: 'm4' },
        { composerFocused: true, height: 320.5, messageShown: () => false },
      ],
      [
        { type: 'quoteClicked', id: 'm4' },
        { composerFocused: true, height: 320.5, messageShown: () => false },
      ],
    ]);
    expect(moves([...first.commands, ...again.commands])).toEqual([]);
    expect(again.state.target).toMatchObject({ id: 'm4', phase: 'landed' });
    expect(restores(close(again.state, 418).commands)).toEqual([
      { type: 'restoreScroll', top: 1128 },
    ]);
  });

  it('J1′ a press shown at the press whose click goes to the original lets the move win (25)', () => {
    const { state, commands } = run(focusedAway(), [
      [
        { type: 'pageAction', quote: 'm4' },
        { composerFocused: true, height: 320.5, messageShown: () => true },
      ],
      [
        { type: 'quoteClicked', id: 'm4' },
        { composerFocused: true, height: 320.5, messageShown: () => false },
      ],
      [{ type: 'targetLoaded', id: 'm4' }, { composerFocused: true }],
      [
        { type: 'targetScrolled', id: 'm4', movedUp: true, moved: true },
        { composerFocused: true, height: 320.5, distance: 700 },
      ],
    ]);
    expect(
      commands.filter((command) => command.type === 'scrollToMessage'),
    ).toEqual([{ type: 'scrollToMessage', id: 'm4' }]);
    expect(restores(close(state, 700).commands)).toEqual([]);
  });

  for (const [name, after] of [
    ['the app keeps the place', { top: -500, scrollTop: 1426 }],
    ['the browser keeps the place', { top: -600, scrollTop: 1526 }],
  ] as const) {
    it(`P4 a quote never found goes back to the place, moved with older pages (${name})`, () => {
      const { state, commands } = run(focusedAway(), [
        [
          { type: 'pageAction', quote: 'gone' },
          { composerFocused: true, height: 320.5, messageShown: () => false },
        ],
        [
          { type: 'quoteClicked', id: 'gone' },
          { composerFocused: true, height: 320.5, messageShown: () => false },
        ],
        [
          { type: 'olderArriving' },
          {
            composerFocused: true,
            height: 320.5,
            scrollTop: 1426,
            firstMessage: { id: 'm0', top: -600 },
          },
        ],
        [
          { type: 'olderLoaded' },
          {
            composerFocused: true,
            height: 320.5,
            scrollTop: after.scrollTop,
            messageTop: (id) => (id === 'm0' ? after.top : null),
          },
        ],
        [
          { type: 'targetMissing' },
          { composerFocused: true, height: 320.5, distance: 446.5 },
        ],
      ]);
      expect(state.target).toBeNull();
      expect(
        moves(commands).filter((command) => command.type !== 'scrollBy'),
      ).toEqual([]);
      expect(restores(close(state, 518).commands)).toEqual([
        { type: 'restoreScroll', top: 1228 },
      ]);
    });
  }

  it('P4 older pages while following move nothing to go back to', () => {
    const { state, commands } = run(keyboardOpen(opened().state).state, [
      [
        { type: 'olderArriving' },
        { composerFocused: true, firstMessage: { id: 'm0', top: -600 } },
      ],
      [
        { type: 'olderLoaded' },
        { composerFocused: true, messageTop: () => -500 },
      ],
    ]);
    expect(moves(commands)).toEqual([]);
    expect(state.keyboard?.restoreTop).toBe(3501);
  });
});
