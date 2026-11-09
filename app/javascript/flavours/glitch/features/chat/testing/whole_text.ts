export const wholeText =
  (text: string) => (_content: string, element: Element | null) =>
    element?.textContent === text &&
    !Array.from(element.children).some((child) => child.textContent === text);
