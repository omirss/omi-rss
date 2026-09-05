import type { ComponentType } from "preact";

export interface ReadingIconProps {
  size?: number;
  class?: string;
}

function createIcon(paths: preact.ComponentChildren): ComponentType<ReadingIconProps> {
  function Icon({ size = 20, class: className }: ReadingIconProps) {
    return (
      <svg
        width={size}
        height={size}
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.8"
        stroke-linecap="round"
        stroke-linejoin="round"
        aria-hidden="true"
        class={className}
      >
        {paths}
      </svg>
    );
  }
  return Icon;
}

export const StarIcon = createIcon(
  <path d="M12 3.8l2.5 5.1 5.6.8-4 4 .9 5.6-5-2.6-5 2.6.9-5.6-4-4 5.6-.8z" />,
);

export const ExternalLinkIcon = createIcon(
  <>
    <path d="M13.5 5H18a1 1 0 0 1 1 1v4.5" />
    <path d="M19 5l-8 8" />
    <path d="M18.5 14v4a1.5 1.5 0 0 1-1.5 1.5H6.5A1.5 1.5 0 0 1 5 18V7a1.5 1.5 0 0 1 1.5-1.5h4" />
  </>,
);

export const ChevronRightIcon = createIcon(<path d="M10 6l6 6-6 6" />);

export const CheckDoubleIcon = createIcon(
  <>
    <path d="M2.8 12.6l3.6 3.6 7.8-8.4" />
    <path d="M10.8 16.2l.9.9 8.6-9.3" />
  </>,
);

export const LinkIcon = createIcon(
  <>
    <path d="M10.5 13.5a4.2 4.2 0 0 0 6 0l3-3a4.24 4.24 0 0 0-6-6l-1.4 1.4" />
    <path d="M13.5 10.5a4.2 4.2 0 0 0-6 0l-3 3a4.24 4.24 0 0 0 6 6l1.4-1.4" />
  </>,
);
