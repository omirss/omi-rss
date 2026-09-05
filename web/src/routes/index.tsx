import { Link, route } from "@neutron-build/core/client";
import { AppShell } from "../components/AppShell.js";
import { EmptyState } from "../components/states.js";
import { CompassIcon, PlusIcon, RssIcon } from "../components/Icons.js";

export const config = { mode: "app" };

export default function HomePage() {
  return (
    <AppShell
      title="Home"
      actions={
        <Link to={route("/discover")} class="btn btn-secondary btn-sm">
          <PlusIcon size={15} />
          Add feed
        </Link>
      }
    >
      <div class="page">
        <EmptyState
          icon={<RssIcon size={24} />}
          title="No articles yet"
          description="Subscribe to your first feed and fresh articles will land here."
          action={
            <Link to={route("/discover")} class="btn btn-primary">
              <CompassIcon size={16} />
              Discover feeds
            </Link>
          }
        />
      </div>
    </AppShell>
  );
}
