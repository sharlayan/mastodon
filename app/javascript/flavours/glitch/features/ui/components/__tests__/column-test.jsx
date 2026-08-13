import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';

import { Column } from '@/flavours/glitch/components/column';
import { ColumnWidthContext } from 'flavours/glitch/features/ui/util/column_width_context';

describe('Column', () => {
  it('applies a customized width from the deck column context', () => {
    render(
      <ColumnWidthContext.Provider value={{ customized: true, width: 520 }}>
        <Column>Content</Column>
      </ColumnWidthContext.Provider>,
    );

    expect(
      screen.getByRole('region').style.getPropertyValue('--column-width'),
    ).toBe('520px');
  });

  it('keeps the stylesheet default when the width is not customized', () => {
    render(
      <ColumnWidthContext.Provider value={{ customized: false, width: 520 }}>
        <Column>Content</Column>
      </ColumnWidthContext.Provider>,
    );

    expect(screen.getByRole('region').getAttribute('style')).toBeNull();
  });
});
