import type {
  PublicTimeline as PublicTimelineLoader,
  sharlayanColumnComponents as ColumnComponents,
  sharlayanRouteDescriptors as RouteDescriptors,
} from '.';

let sharlayanRouteDescriptors: typeof RouteDescriptors;
let sharlayanColumnComponents: typeof ColumnComponents;
let PublicTimeline: typeof PublicTimelineLoader;

beforeAll(async () => {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: vi.fn().mockImplementation(() => ({
      matches: false,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    })),
  });

  ({ sharlayanColumnComponents, sharlayanRouteDescriptors, PublicTimeline } =
    await import('.'));
});

describe('Sharlayan route registry', () => {
  it('registers every custom multi-column component in one descriptor', () => {
    expect(Object.keys(sharlayanColumnComponents)).toEqual([
      'CONVERSATION',
      'ANTENNA',
      'REACTIONS',
      'BOARD_ANNOUNCEMENTS',
      'CLIP',
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

  it('opens the federated timeline at /public', () => {
    expect(
      sharlayanRouteDescriptors.find(({ key }) => key === 'public'),
    ).toMatchObject({
      path: '/public',
      lazyComponent: PublicTimeline,
    });
  });

  it('registers the remaining Firehose routes with their feed types', () => {
    const firehoseRoutes = sharlayanRouteDescriptors
      .filter(({ key }) => ['community', 'remote'].includes(key))
      .map(({ key, path, componentParams }) => ({
        key,
        path,
        componentParams,
      }));

    expect(firehoseRoutes).toEqual([
      {
        key: 'community',
        path: '/public/local',
        componentParams: { feedType: 'community' },
      },
      {
        key: 'remote',
        path: '/public/remote',
        componentParams: { feedType: 'public:remote' },
      },
    ]);
  });
});
