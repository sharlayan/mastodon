import { IntlProvider } from 'react-intl';

import { cleanup, fireEvent, render, screen } from '@testing-library/react';

import type { ApiPageBlock } from 'flavours/glitch/api_types/pages';

import { EditorBlock } from '../editor_block';

vi.mock('flavours/glitch/initial_state', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  domain: 'm1.social',
}));

vi.mock('flavours/glitch/store', () => ({
  useAppDispatch: () => vi.fn(),
}));

vi.mock('../image_upload_field', () => ({
  ImageUploadField: () => null,
}));

const noMedia = () => null;

const renderNoteBlock = () => {
  const onUpdate = vi.fn();
  const block = { id: 'n1', type: 'note', note: null } as ApiPageBlock;

  render(
    <IntlProvider locale='en'>
      <EditorBlock
        block={block}
        depth={0}
        onUpdate={onUpdate}
        onRemove={vi.fn()}
        onMove={vi.fn()}
        onAddChild={vi.fn()}
        onMediaUploaded={vi.fn()}
        getMedia={noMedia}
      />
    </IntlProvider>,
  );

  return {
    input: screen.getByPlaceholderText<HTMLInputElement>('Post ID or URL'),
    onUpdate,
  };
};

const typeInto = (input: HTMLInputElement, text: string) => {
  for (let index = 1; index <= text.length; index += 1) {
    fireEvent.change(input, { target: { value: text.slice(0, index) } });
  }
};

describe('EditorBlock note input', () => {
  afterEach(() => {
    cleanup();
  });

  it('keeps the typed URL and extracts the post id on blur', () => {
    const { input, onUpdate } = renderNoteBlock();
    const url = 'https://m1.social/@alice/112233';

    typeInto(input, url);

    expect(input.value).toBe(url);
    expect(onUpdate).not.toHaveBeenCalled();

    fireEvent.blur(input);

    expect(onUpdate).toHaveBeenCalledWith('n1', { note: '112233' });
  });

  it('accepts a bare post id', () => {
    const { input, onUpdate } = renderNoteBlock();

    fireEvent.change(input, { target: { value: ' 445566 ' } });
    fireEvent.blur(input);

    expect(onUpdate).toHaveBeenCalledWith('n1', { note: '445566' });
  });

  it('rejects URLs from other servers', () => {
    const { input, onUpdate } = renderNoteBlock();

    fireEvent.change(input, {
      target: { value: 'https://other.example/@bob/778899' },
    });
    fireEvent.blur(input);

    expect(onUpdate).toHaveBeenCalledWith('n1', { note: null });
    expect(input.getAttribute('aria-invalid')).toBe('true');
    expect(input.value).toBe('https://other.example/@bob/778899');
  });
});
