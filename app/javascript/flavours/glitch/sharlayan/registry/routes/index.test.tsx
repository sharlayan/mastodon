import type {
  sharlayanColumnComponents as ColumnComponents,
  sharlayanRouteDescriptors as RouteDescriptors,
} from '.';

let sharlayanRouteDescriptors: typeof RouteDescriptors;
let sharlayanColumnComponents: typeof ColumnComponents;

beforeAll(async () => {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: vi.fn().mockImplementation(() => ({
      matches: false,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    })),
  });

  ({ sharlayanColumnComponents, sharlayanRouteDescriptors } =
    await import('.'));
});

describe('Sharlayan route registry', () => {
  it('registers every custom multi-column component in one descriptor', () => {
    expect(Object.keys(sharlayanColumnComponents)).toEqual([
      'CONVERSATION',
      'ANTENNA',
      'ADMIN_TIMELINE',
      'REACTIONS',
      'BOARD_ANNOUNCEMENTS',
    ]);
  });

  it('uses unique keys', () => {
    const keys = sharlayanRouteDescriptors.map(({ key }) => key);

    expect(new Set(keys).size).toBe(keys.length);
  });

  it.each([
    ['clip-new', 'clip-show'],
    ['clip-edit', 'clip-show'],
    ['page-new', 'page-show'],
    ['page-edit', 'page-show'],
    ['page-show', 'pages'],
    ['circle-edit', 'circles'],
    ['circle-members', 'circles'],
    ['antenna-edit', 'antenna-show'],
    ['antenna-show', 'antennas'],
    ['account-page', 'account-pages'],
  ])('places %s before %s', (earlier, later) => {
    const keys = sharlayanRouteDescriptors.map(({ key }) => key);

    expect(keys.indexOf(earlier)).toBeLessThan(keys.indexOf(later));
  });

  it('retains exact matching for collection routes', () => {
    const exactRoutes = sharlayanRouteDescriptors
      .filter(({ exact }) => exact)
      .map(({ key }) => key);

    expect(exactRoutes).toEqual(
      expect.arrayContaining(['public', 'community', 'pages', 'account-pages']),
    );
  });
});
