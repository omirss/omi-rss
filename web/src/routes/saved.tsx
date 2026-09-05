import { AppShell, PagePlaceholder } from "../components/AppShell.js";

export const config = { mode: "app" };

export default function SavedPage() {
  return (
    <AppShell title="Saved">
      <PagePlaceholder
        title="No saved articles"
        description="Articles you star while reading are collected here for later."
      />
    </AppShell>
  );
}
