import type { ComponentType } from "preact";

export interface IconProps {
  size?: number;
  class?: string;
}

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

export const MenuIcon = createIcon(
  <>
    <path d="M4 6h16" />
    <path d="M4 12h16" />
    <path d="M4 18h16" />
  </>,
);

export const CloseIcon = createIcon(
  <>
    <path d="M6 6l12 12" />
    <path d="M18 6L6 18" />
  </>,
);

export const HomeIcon = createIcon(
  <>
    <path d="M4 11l8-7 8 7" />
    <path d="M6 9.5V20h12V9.5" />
    <path d="M10 20v-5h4v5" />
  </>,
);

export const BookmarkIcon = createIcon(
  <>
    <path d="M7 4h10a1 1 0 0 1 1 1v15l-6-3.5L6 20V5a1 1 0 0 1 1-1z" />
  </>,
);

export const SearchIcon = createIcon(
  <>
    <circle cx="11" cy="11" r="6.5" />
    <path d="M20 20l-4.4-4.4" />
  </>,
);

export const CompassIcon = createIcon(
  <>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M15.5 8.5l-2 5-5 2 2-5 5-2z" />
  </>,
);

export const FolderIcon = createIcon(
  <>
    <path d="M4 6a1 1 0 0 1 1-1h4l2 2.5h8a1 1 0 0 1 1 1V18a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6z" />
  </>,
);

export const AnalyticsIcon = createIcon(
  <>
    <path d="M5 20V10" />
    <path d="M12 20V4" />
    <path d="M19 20v-7" />
  </>,
);

export const StatisticsIcon = createIcon(
  <>
    <path d="M4 20h16" />
    <path d="M6 16l4-5 3 3 5-7" />
  </>,
);

export const SettingsIcon = createIcon(
  <>
    <circle cx="12" cy="12" r="3" />
    <path d="M12 3v2.5M12 18.5V21M4.2 7.5l2.2 1.2M17.6 15.3l2.2 1.2M4.2 16.5l2.2-1.2M17.6 8.7l2.2-1.2" />
  </>,
);

export const LogoutIcon = createIcon(
  <>
    <path d="M14 4H6a1 1 0 0 0-1 1v14a1 1 0 0 0 1 1h8" />
    <path d="M10 12h10" />
    <path d="M17 9l3 3-3 3" />
  </>,
);

export const SunIcon = createIcon(
  <>
    <circle cx="12" cy="12" r="4" />
    <path d="M12 3v2M12 19v2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M3 12h2M19 12h2M5.6 18.4L7 17M17 7l1.4-1.4" />
  </>,
);

export const MoonIcon = createIcon(<path d="M20 13.5A8 8 0 1 1 10.5 4 6.5 6.5 0 0 0 20 13.5z" />);

export const MonitorIcon = createIcon(
  <>
    <rect x="3.5" y="5" width="17" height="11" rx="1" />
    <path d="M9 20h6" />
    <path d="M12 16v4" />
  </>,
);

export const CheckIcon = createIcon(<path d="M5 12.5l4.5 4.5L19 7.5" />);

export const AlertIcon = createIcon(
  <>
    <path d="M12 4l9 15.5H3L12 4z" />
    <path d="M12 10v4" />
    <path d="M12 17.2v.1" />
  </>,
);

export const InfoIcon = createIcon(
  <>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M12 11v5" />
    <path d="M12 8v.1" />
  </>,
);

export const CheckCircleIcon = createIcon(
  <>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M8.5 12.5l2.5 2.5 4.5-5" />
  </>,
);

export const ErrorCircleIcon = createIcon(
  <>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M12 8v5" />
    <path d="M12 16v.1" />
  </>,
);

export const ChevronLeftIcon = createIcon(<path d="M14 6l-6 6 6 6" />);

export const UserIcon = createIcon(
  <>
    <circle cx="12" cy="8.5" r="3.5" />
    <path d="M5 20a7 7 0 0 1 14 0" />
  </>,
);

export const RssIcon = createIcon(
  <>
    <path d="M5 11a8 8 0 0 1 8 8" />
    <path d="M5 5a14 14 0 0 1 14 14" />
    <circle cx="6.5" cy="17.5" r="1.3" fill="currentColor" stroke="none" />
  </>,
);

export const EyeIcon = createIcon(
  <>
    <path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z" />
    <circle cx="12" cy="12" r="3" />
  </>,
);

export const EyeOffIcon = createIcon(
  <>
    <path d="M4 4l16 16" />
    <path d="M10.6 6a9.8 9.8 0 0 1 1.4-.1c6 0 9.5 6.1 9.5 6.1a17 17 0 0 1-3 3.6" />
    <path d="M6.6 7.3A16 16 0 0 0 2.5 12S6 18.1 12 18.1a9 9 0 0 0 4-.9" />
    <path d="M9.9 10a3 3 0 0 0 4.2 4.2" />
  </>,
);

export const PlusIcon = createIcon(<path d="M12 5v14M5 12h14" />);

export const RefreshIcon = createIcon(
  <>
    <path d="M20 12a8 8 0 1 1-2.3-5.6" />
    <path d="M20 4v4h-4" />
  </>,
);

export const FileTextIcon = createIcon(
  <>
    <path d="M6 3h8l4 4v14a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z" />
    <path d="M14 3v4h4" />
    <path d="M8.5 12h7M8.5 15.5h7M8.5 19h4" />
  </>,
);

export const GlobeIcon = createIcon(
  <>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M3.5 12h17" />
    <path d="M12 3.5c2.2 2.3 3.4 5.3 3.4 8.5s-1.2 6.2-3.4 8.5c-2.2-2.3-3.4-5.3-3.4-8.5s1.2-6.2 3.4-8.5z" />
  </>,
);
