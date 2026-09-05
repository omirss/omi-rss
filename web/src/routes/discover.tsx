import { AppShell, PagePlaceholder } from "../components/AppShell.js";

export const config = { mode: "app" };

export default function DiscoverPage() {
  return (
    <AppShell title="Discover">
      <PagePlaceholder
        title="Discover new feeds"
        description="Browse curated categories, search the catalog, or add a feed by URL."
      />
    </AppShell>
  );
}
