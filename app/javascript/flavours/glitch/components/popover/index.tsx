import { useEffect } from 'react';

import type {
  ReferenceType,
  Placement,
  OffsetOptions,
  Strategy,
} from '@floating-ui/react-dom';
import {
  useFloating,
  autoUpdate,
  inline,
  offset as offsetMiddleware,
  shift,
  flip as flipMiddleware,
  size,
  hide,
} from '@floating-ui/react-dom';

import { useOnClickOutside } from '@/flavours/glitch/hooks/useOnClickOutside';

import { Portal } from './portal';

export interface PopoverProps {
  /**
   * Set the visibility of the popover
   */
  isOpen?: boolean;
  /**
   * Callback triggered when the popover needs to be closed
   * (e.g. because the Esc key was pressed).
   */
  onClose: (e: Event) => void;
  /**
   * Pass an element that the popover should be attached to.
   * Must come from `useState`, not `useRef`.
   */
  reference: ReferenceType | null;
  /**
   * Pass the popover element (useful if you also need the element
   * in the parent and already have it in state).
   * Must come from `useState`, not `useRef`.
   */
  popoverElement?: HTMLElement | null;
  /**
   * Control which element the popover will be rendered into.
   * Passing `null` will render the popover in place.
   */
  container?: HTMLElement | null;
  /**
   * Control where the overlay element is positioned in relation
   * to the reference element
   */
  placement?: Placement;
  /**
   * Control the distance between popover and reference
   */
  offset?: OffsetOptions;
  /**
   * Allow the popover to flip to the other side of the reference
   * if there's no room in the specified direction. Enabled by default.
   */
  flip?: boolean;
  /**
   * Change the positioning strategy, defaults to 'fixed'
   * but can be changed to 'absolute'
   */
  strategy?: Strategy;
  /**
   * Adapt the popover's width to match that of the reference,
   * useful when attached to text input.
   */
  matchReferenceWidth?: boolean;
  /**
   * Control whether to close the popover when clicking outside
   * of it (enabled by default).
   */
  closeOnClickOutside?: boolean;
  /**
   * Keep the whole popover on what can be seen of the screen (the visual
   * viewport), which also shrinks when a phone shows its keyboard. The room
   * it has is given to it as `--popover-available-height` and
   * `--popover-available-width`, for it to shrink to. When there is little
   * room beside the reference, it covers the reference instead.
   * Off by default.
   */
  fitViewport?: boolean;
  /**
   * Render prop that must return the popover element.
   */
  children: (value: {
    /**
     * The popover's final computed placement. Can be used to
     * adjust the popover's style based on its position.
     */
    placement: Placement | undefined;
    /**
     * Re-computes the popover's position – call this when an
     * action inside of the popover has changed its size.
     */
    update: () => void;
    /**
     * These props must be passed to the popover element to
     * enable it to be sized and positioned. The `ref` prop
     * is not passed when the `popoverElement` prop is provided.
     */
    props: PopoverChildProps;
  }) => React.ReactNode;
}

export interface PopoverChildProps {
  ref?: React.RefCallback<HTMLElement>;
  style: React.CSSProperties;
  'data-popover-placement': Placement;
  'data-popover-reference-hidden'?: boolean;
  'data-popover-escaped'?: boolean;
}

const VIEWPORT_PADDING = 8;
// Less room than this beside the reference, and the popover covers the reference rather than shrink further.
const ROOM_BESIDE_REFERENCE = 200;

const fitViewportMiddleware = [
  flipMiddleware({ padding: VIEWPORT_PADDING }),
  size({
    padding: VIEWPORT_PADDING,
    apply({ availableWidth, availableHeight, elements }) {
      const screenHeight =
        (window.visualViewport?.height ?? window.innerHeight) -
        VIEWPORT_PADDING * 2;
      const height =
        availableHeight >= ROOM_BESIDE_REFERENCE
          ? availableHeight
          : screenHeight;
      elements.floating.style.setProperty(
        '--popover-available-height',
        `${Math.max(0, Math.floor(height))}px`,
      );
      elements.floating.style.setProperty(
        '--popover-available-width',
        `${Math.max(0, Math.floor(availableWidth))}px`,
      );
    },
  }),
  shift({ padding: VIEWPORT_PADDING, crossAxis: true }),
];

export const Popover: React.FC<PopoverProps> = ({
  isOpen,
  onClose,
  reference,
  popoverElement,
  placement = 'bottom',
  offset,
  strategy = 'absolute',
  flip = true,
  container,
  matchReferenceWidth = false,
  closeOnClickOutside = true,
  fitViewport = false,
  children,
}) => {
  const {
    placement: computedPlacement,
    update,
    refs,
    floatingStyles,
    middlewareData,
    elements,
  } = useFloating({
    elements: {
      reference,
      floating: popoverElement,
    },
    placement,
    strategy,
    whileElementsMounted: autoUpdate,
    middleware: [
      offsetMiddleware(offset),
      inline(),
      ...(fitViewport
        ? fitViewportMiddleware
        : [shift(), flip ? flipMiddleware() : null]),
      matchReferenceWidth
        ? size({
            apply({ rects, elements }) {
              Object.assign(elements.floating.style, {
                minWidth: `${rects.reference.width}px`,
              });
            },
          })
        : null,
      hide(),
    ],
  });

  // Close when clicking outside the popover
  useOnClickOutside(
    [
      elements.floating,
      // Only pass reference if it's not a "virtual element"
      elements.reference instanceof Element ? elements.reference : null,
    ],
    (e) => {
      onClose(e);
    },
    isOpen && closeOnClickOutside,
  );

  // A phone's keyboard shrinks only what can be seen, which moves nothing that autoUpdate watches.
  useEffect(() => {
    const viewport = window.visualViewport;
    if (!isOpen || !fitViewport || !viewport) {
      return () => null;
    }

    viewport.addEventListener('resize', update);
    viewport.addEventListener('scroll', update);

    return () => {
      viewport.removeEventListener('resize', update);
      viewport.removeEventListener('scroll', update);
    };
  }, [isOpen, fitViewport, update]);

  // Close when pressing Escape
  useEffect(() => {
    if (!isOpen) {
      return () => null;
    }

    function closeOnEscape(event: KeyboardEvent) {
      if (event.key === 'Escape') {
        event.preventDefault();
        onClose(event);
      }
    }

    document.addEventListener('keydown', closeOnEscape);

    return () => {
      document.removeEventListener('keydown', closeOnEscape);
    };
  }, [isOpen, onClose]);

  if (!isOpen) {
    return null;
  }

  const props: PopoverChildProps = {
    style: floatingStyles,
    'data-popover-placement': computedPlacement,
    'data-popover-reference-hidden': middlewareData.hide?.referenceHidden,
    'data-popover-escaped': middlewareData.hide?.escaped,
  };
  if (!popoverElement) {
    props.ref = refs.setFloating;
  }

  return (
    <Portal container={container}>
      {children({
        placement: computedPlacement,
        update,
        props,
      })}
    </Portal>
  );
};
