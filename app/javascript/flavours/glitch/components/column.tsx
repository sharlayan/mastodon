import { forwardRef, useRef, useImperativeHandle } from 'react';
import type { Ref } from 'react';

import { useColumnWidthContext } from 'flavours/glitch/features/ui/util/column_width_context';
import { scrollTop } from 'flavours/glitch/scroll';

export interface ColumnRef {
  scrollTop: () => void;
  node: HTMLDivElement | null;
}

interface ColumnProps {
  children?: React.ReactNode;
  label?: string;
  bindToDocument?: boolean;
  className?: string;
}

export const Column = forwardRef<ColumnRef, ColumnProps>(
  ({ children, label, bindToDocument, className }, ref: Ref<ColumnRef>) => {
    const nodeRef = useRef<HTMLDivElement>(null);
    const { customized, width } = useColumnWidthContext();

    useImperativeHandle(ref, () => ({
      node: nodeRef.current,

      scrollTop() {
        let scrollable = null;

        if (bindToDocument) {
          scrollable = document.scrollingElement;
        } else {
          scrollable = nodeRef.current?.querySelector('.scrollable');
        }

        if (!scrollable) {
          return;
        }

        scrollTop(scrollable);
      },
    }));

    const classNames = ['column', className].filter(Boolean).join(' ');

    return (
      <div
        role='region'
        aria-label={label}
        className={classNames}
        ref={nodeRef}
        style={
          customized && width
            ? ({ '--column-width': `${width}px` } as React.CSSProperties)
            : undefined
        }
      >
        {children}
      </div>
    );
  },
);

Column.displayName = 'Column';

// eslint-disable-next-line import/no-default-export
export default Column;
