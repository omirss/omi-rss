import { AppShell, PagePlaceholder } from "../components/AppShell.js";

export const config = { mode: "app" };

export default function SearchPage() {
  return (
    <AppShell title="Search">
      <PagePlaceholder
        title="Search your library"
        description="Find articles by title, summary, or content across every feed you follow."
      />
    </AppShell>
  );
}
