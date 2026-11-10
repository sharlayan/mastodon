import { initBoardAnnouncementMedia } from './board_announcement_media';

const setup = () => {
  document.body.innerHTML = '';
  const container = document.createElement('div');
  container.dataset.boardAnnouncementMedia = 'true';
  container.dataset.destroyUrl = '/admin/board_announcements/attachments/0';
  container.dataset.fieldName = 'attachment_ids[]';
  container.dataset.labelRemoveError = 'Could not remove';
  container.dataset.existing = JSON.stringify([
    {
      id: '5',
      type: 'file',
      url: '/a.pdf',
      preview_url: '/a.pdf',
      file_name: 'a.pdf',
    },
  ]);
  document.body.appendChild(container);
  initBoardAnnouncementMedia();
  return container;
};

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('board announcement media', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('keeps the attachment when removal fails', async () => {
    const fetchMock = vi.fn(() =>
      Promise.resolve(new Response(null, { status: 500 })),
    );
    vi.stubGlobal('fetch', fetchMock);
    const container = setup();

    container
      .querySelector<HTMLButtonElement>('.board-announcement-media__remove')
      ?.click();
    await flush();

    expect(fetchMock).toHaveBeenCalledWith(
      '/admin/board_announcements/attachments/5',
      expect.objectContaining({ method: 'DELETE' }),
    );
    expect(container.querySelector('input[type="hidden"]')).not.toBeNull();
    expect(
      container.querySelector('.board-announcement-media__status')?.textContent,
    ).toBe('Could not remove');
  });

  it('removes the attachment after a successful delete', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(() => Promise.resolve(new Response(null, { status: 200 }))),
    );
    const container = setup();

    container
      .querySelector<HTMLButtonElement>('.board-announcement-media__remove')
      ?.click();
    await flush();

    expect(container.querySelector('input[type="hidden"]')).toBeNull();
  });
});
