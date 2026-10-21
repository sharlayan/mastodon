import { computeNavigationOrder, isNavigationItemAlwaysVisible } from './items';
import type { NavigationPanelItem } from './items';

export function getRedesignNavigationKeys({
  order,
  hidden,
  available,
  showHidden = false,
}: {
  order?: string[];
  hidden?: Record<string, boolean>;
  available: string[];
  showHidden?: boolean;
}) {
  return computeNavigationOrder(order).filter(
    (key): key is NavigationPanelItem =>
      available.includes(key) &&
      (showHidden || isNavigationItemAlwaysVisible(key) || !hidden?.[key]),
  );
}
