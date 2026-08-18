import { fromJS } from 'immutable';

let SharlayanStatusReactionButton;

beforeAll(async () => {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: vi.fn().mockImplementation(() => ({
      matches: false,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    })),
  });

  ({ SharlayanStatusReactionButton } = await import('../status_action_bar'));
});

describe('Sharlayan status action bar helpers', () => {
  it('renders nothing when reactions are disabled', () => {
    const status = fromJS({ id: '1' });
    const output = SharlayanStatusReactionButton({ enabled: false, status, permissions: 1, onReactionAdd: vi.fn() });
    expect(output).toBeNull();
  });
});
