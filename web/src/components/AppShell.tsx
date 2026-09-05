import { useEffect, useState } from "preact/hooks";
import type { ComponentChildren, VNode } from "preact";
import { NavLink, useNavigate } from "@neutron-build/core/client";
import type { RouteHref } from "@neutron-build/core/client";
import { useSession } from "../lib/auth.js";
import { AccountMenu } from "./AccountMenu.js";
import { EmptyState } from "./states.js";
import {
  AnalyticsIcon,
  BookmarkIcon,
  ChevronLeftIcon,
  CloseIcon,
  CompassIcon,
  FolderIcon,
  HomeIcon,
  MenuIcon,
  RssIcon,
  SearchIcon,
  StatisticsIcon,
} from "./Icons.js";

export interface NavItem {
  to: RouteHref;
  label: string;
  icon: VNode;
  end?: boolean;
}

export interface NavSection {
  label: string;
  items: NavItem[];
}

const NAV_SECTIONS: NavSection[] = [
  {
    label: "Reading",
    items: [
      { to: "/", label: "Home", icon: <HomeIcon />, end: true },
      { to: "/saved", label: "Saved", icon: <BookmarkIcon /> },
      { to: "/search", label: "Search", icon: <SearchIcon /> },
      { to: "/discover", label: "Discover", icon: <CompassIcon /> },
      { to: "/folders", label: "Folders", icon: <FolderIcon /> },
    ],
  },
  {
    label: "Insights",
    items: [
      { to: "/analytics", label: "Analytics", icon: <AnalyticsIcon /> },
      { to: "/statistics", label: "Statistics", icon: <StatisticsIcon /> },
    ],
  },
];

const DRAWER_COLLAPSED_KEY = "omi.drawer.collapsed";

export function AppShell({
  title,
  actions,
  children,
  drawerExtra,
}: {
  title: string;
  actions?: ComponentChildren;
  children: ComponentChildren;
  drawerExtra?: ComponentChildren;
}) {
  const { status } = useSession();
  const navigate = useNavigate();
  const [mobileOpen, setMobileOpen] = useState(false);
  const [collapsed, setCollapsed] = useState(false);

  useEffect(() => {
    try {
      setCollapsed(localStorage.getItem(DRAWER_COLLAPSED_KEY) === "1");
    } catch {
      setCollapsed(false);
    }
  }, []);

  useEffect(() => {
    if (status === "anonymous") {
      navigate("/login");
    }
  }, [status, navigate]);

  if (status !== "authenticated") {
    return <ShellLoading />;
  }

  const toggleCollapsed = () => {
    setCollapsed((current) => {
      const next = !current;
      try {
        localStorage.setItem(DRAWER_COLLAPSED_KEY, next ? "1" : "0");
      } catch {
        return next;
      }
      return next;
    });
  };

  return (
    <div class="shell">
      {mobileOpen ? <div class="drawer-mobile-backdrop" onClick={() => setMobileOpen(false)} /> : null}
      <aside class={`shell-drawer glass-panel${mobileOpen ? " shell-drawer-open" : ""}${collapsed ? " shell-drawer-collapsed" : ""}`}>
        <div class="drawer-header">
          <span class="drawer-title">Omi RSS</span>
          <button type="button" class="drawer-collapse drawer-collapse-btn" onClick={toggleCollapsed} aria-label="Collapse sidebar">
            <ChevronLeftIcon size={16} />
          </button>
          <button
            type="button"
            class="drawer-collapse drawer-close-btn"
            onClick={() => setMobileOpen(false)}
            aria-label="Close menu"
          >
            <CloseIcon size={16} />
          </button>
        </div>
        <nav class="drawer-scroll">
          {NAV_SECTIONS.map((section) => (
            <div key={section.label} class="drawer-section">
              <div class="drawer-section-label">{section.label}</div>
              {section.items.map((item) => (
                <div key={item.to} class="drawer-link-row" onClick={() => setMobileOpen(false)}>
                  <NavLink to={item.to} end={item.end} class="drawer-link" activeClass="drawer-link-active">
                    {item.icon}
                    <span class="shell-expand-label">{item.label}</span>
                  </NavLink>
                </div>
              ))}
            </div>
          ))}
          {drawerExtra}
        </nav>
      </aside>
      <div class="shell-main">
        <header class="topbar glass-card">
          <button
            type="button"
            class="btn btn-ghost btn-icon topbar-menu-btn"
            onClick={() => setMobileOpen(true)}
            aria-label="Open menu"
          >
            <MenuIcon size={19} />
          </button>
          <h1 class="topbar-title">{title}</h1>
          {actions}
          <div class="topbar-spacer" />
          <AccountMenu />
        </header>
        <main class="shell-content">{children}</main>
      </div>
    </div>
  );
}

export function ShellLoading() {
  return (
    <div class="loading-block">
      <span class="spinner" />
      Loading
    </div>
  );
}

export function PagePlaceholder({ title, description }: { title: string; description: string }) {
  return (
    <div class="page">
      <EmptyState icon={<RssIcon size={24} />} title={title} description={description} />
    </div>
  );
}
