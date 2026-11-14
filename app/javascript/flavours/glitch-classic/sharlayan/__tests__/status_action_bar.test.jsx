import { fromJS } from 'immutable';

let sharlayanAddToClipMenuItem;
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

  ({ sharlayanAddToClipMenuItem, SharlayanStatusReactionButton } =
    await import('../status_action_bar'));
});

const intl = { formatMessage: ({ id }) => id };

describe('Sharlayan status action bar helpers', () => {
  it('omits the clip menu item unless enabled', () => {
    const dispatch = vi.fn();

    expect(sharlayanAddToClipMenuItem(intl, { enabled: false, statusId: '1', dispatch })).toBeNull();

    const item = sharlayanAddToClipMenuItem(intl, { enabled: true, statusId: '1', dispatch });
    expect(item).toMatchObject({ text: 'status.add_to_clip' });
  });

  it('opens the CLIP_ADD modal for the status when the menu action fires', () => {
    const dispatch = vi.fn();
    const item = sharlayanAddToClipMenuItem(intl, { enabled: true, statusId: '42', dispatch });

    item.action();

    expect(dispatch).toHaveBeenCalledTimes(1);
    const action = dispatch.mock.calls[0][0];
    expect(action.type).toBe('MODAL_OPEN');
    expect(action.payload).toMatchObject({
      modalType: 'CLIP_ADD',
      modalProps: { statusId: '42' },
    });
  });

  it('renders nothing when reactions are disabled', () => {
    const status = fromJS({ id: '1' });
    const output = SharlayanStatusReactionButton({ enabled: false, status, permissions: 1, onReactionAdd: vi.fn() });
    expect(output).toBeNull();
  });
});
