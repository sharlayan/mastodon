import { cleanup, fireEvent, render } from '@testing-library/react';

import { FrozenDecorationImage } from '../avatar_decoration_image';

vi.mock('@/flavours/glitch-classic/store', () => ({ useAppSelector: vi.fn() }));

const drawImage = vi.fn();

const markLoaded = (image: HTMLImageElement) => {
  Object.defineProperty(image, 'naturalWidth', { value: 512 });
  Object.defineProperty(image, 'naturalHeight', { value: 256 });
  fireEvent.load(image);
};

beforeEach(() => {
  drawImage.mockClear();
  vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue({
    drawImage,
  } as unknown as ReturnType<HTMLCanvasElement['getContext']>);
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe('<FrozenDecorationImage />', () => {
  it('uses the server still image when one exists', () => {
    const { container, rerender } = render(
      <FrozenDecorationImage url='/a.gif' staticUrl='/a.png' playing={false} />,
    );
    expect(container.querySelector('img')?.getAttribute('src')).toBe('/a.png');
    expect(container.querySelector('canvas')).toBeNull();

    rerender(<FrozenDecorationImage url='/a.gif' staticUrl='/a.png' playing />);
    expect(container.querySelector('img')?.getAttribute('src')).toBe('/a.gif');
  });

  it('holds an APNG on its first frame and plays it only while playing', () => {
    const { container, rerender } = render(
      <FrozenDecorationImage url='/a.png' staticUrl='/a.png' playing={false} />,
    );
    const canvas = container.querySelector('canvas');
    if (!canvas) throw new Error('canvas missing');
    expect(canvas.style.visibility).toBe('hidden');

    markLoaded(container.querySelector('img') as HTMLImageElement);

    expect(drawImage).toHaveBeenCalledTimes(1);
    expect(container.querySelector('img')).toBeNull();
    expect(canvas.style.visibility).toBe('');
    expect(canvas.width / canvas.height).toBe(2);

    rerender(<FrozenDecorationImage url='/a.png' staticUrl='/a.png' playing />);
    const playing = container.querySelector('img') as HTMLImageElement;
    expect(canvas.style.display).toBe('');
    expect(playing.style.visibility).toBe('hidden');

    markLoaded(playing);
    expect(canvas.style.display).toBe('none');
    expect(playing.style.visibility).toBe('');
    expect(drawImage).toHaveBeenCalledTimes(1);

    rerender(
      <FrozenDecorationImage url='/a.png' staticUrl='/a.png' playing={false} />,
    );
    expect(container.querySelector('img')).toBeNull();
    expect(canvas.style.display).toBe('');
  });

  it('keeps showing the decoration when the browser cannot draw it', () => {
    vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(null);
    const { container } = render(
      <FrozenDecorationImage url='/a.png' staticUrl='/a.png' playing={false} />,
    );

    markLoaded(container.querySelector('img') as HTMLImageElement);

    expect(container.querySelector('canvas')).toBeNull();
    expect(container.querySelector('img')?.style.visibility).toBe('');
  });
});
