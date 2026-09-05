import type { ComponentType } from "preact";
import type { IconProps } from "../Icons.js";

function createIcon(paths: preact.ComponentChildren): ComponentType<IconProps> {
  function Icon({ size = 20, class: className }: IconProps) {
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

export const ChevronUpIcon = createIcon(<path d="M6 14l6-6 6 6" />);

export const ChevronDownIcon = createIcon(<path d="M6 10l6 6 6-6" />);

export const PencilIcon = createIcon(
  <>
    <path d="M4 20h4L19 9a2.1 2.1 0 0 0-3-3L5 17v3z" />
    <path d="M13.5 6.5l3 3" />
  </>,
);

export const TrashIcon = createIcon(
  <>
    <path d="M4 7h16" />
    <path d="M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2" />
    <path d="M6 7l1 13a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1l1-13" />
    <path d="M10 11v6M14 11v6" />
  </>,
);

export const UploadIcon = createIcon(
  <>
    <path d="M12 16V4" />
    <path d="M7 9l5-5 5 5" />
    <path d="M4 16v3a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-3" />
  </>,
);

export const DownloadIcon = createIcon(
  <>
    <path d="M12 4v12" />
    <path d="M7 11l5 5 5-5" />
    <path d="M4 20h16" />
  </>,
);

export const KeyIcon = createIcon(
  <>
    <circle cx="8" cy="15" r="4" />
    <path d="M10.8 12.2L20 3" />
    <path d="M16.5 6.5l3 3" />
    <path d="M13.5 9.5l3 3" />
  </>,
);

export const FlameIcon = createIcon(
  <path d="M12 3c1 4-4 5.5-4 9.5a4 4 0 0 0 8 0c0-2-1-3-1.5-4.5C13.5 9.5 14 6 12 3z" />,
);

export const ClockIcon = createIcon(
  <>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M12 7.5V12l3 2" />
  </>,
);

export const StarIcon = createIcon(
  <path d="M12 4l2.4 4.9 5.4.8-3.9 3.8.9 5.4-4.8-2.5-4.8 2.5.9-5.4-3.9-3.8 5.4-.8L12 4z" />,
);

export const TrendUpIcon = createIcon(
  <>
    <path d="M4 17l6-6 3 3 7-7" />
    <path d="M15 7h5v5" />
  </>,
);

export const TrendDownIcon = createIcon(
  <>
    <path d="M4 7l6 6 3-3 7 7" />
    <path d="M15 17h5v-5" />
  </>,
);

export const TrendFlatIcon = createIcon(
  <>
    <path d="M4 12h16" />
    <path d="M16 8l4 4-4 4" />
  </>,
);

export const SparkIcon = createIcon(
  <>
    <path d="M12 3v4M12 17v4M3 12h4M17 12h4" />
    <path d="M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8z" />
  </>,
);
