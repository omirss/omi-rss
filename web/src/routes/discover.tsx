import { useCallback, useEffect, useRef, useState } from "preact/hooks";
import type { JSX } from "preact";
import { AppShell } from "../components/AppShell.js";
import { EmptyState, ErrorState, SkeletonList } from "../components/states.js";
import { useToast } from "../components/Toast.js";
import { useSession } from "../lib/auth.js";
import { CheckIcon, CompassIcon, RssIcon, SearchIcon } from "../components/Icons.js";
import { ApiError, discoveryApi, feedsApi } from "../lib/client.js";
import type { DiscoveryCategory, FeedSuggestion, FeedWithUnread } from "../lib/api-types.js";
import { LinkIcon } from "../components/reading/icons.js";
import { normalizeFeedUrl } from "../components/reading/format.js";
import "../components/reading/reading.css";

export const config = { mode: "app" };

const SEARCH_DEBOUNCE_MS = 400;

type LoadStatus = "loading" | "ready" | "error";

function FeedAvatar({ src, name }: { src?: string; name: string }) {
  return (
    <span class="article-avatar">
      {src ? <img src={src} alt="" loading="lazy" /> : <span class="article-avatar-fallback">{(name || "?").trim().charAt(0).toUpperCase()}</span>}
    </span>
  );
}

export default function DiscoverPage() {
  const { showToast } = useToast();
  const { status: sessionStatus } = useSession();
  const [categories, setCategories] = useState<DiscoveryCategory[] | null>(null);
  const [selectedCategory, setSelectedCategory] = useState("");
  const [suggestions, setSuggestions] = useState<FeedSuggestion[]>([]);
  const [suggestionStatus, setSuggestionStatus] = useState<LoadStatus>("loading");
  const [suggestionError, setSuggestionError] = useState("");
  const [searchText, setSearchText] = useState("");
  const [searchResults, setSearchResults] = useState<FeedSuggestion[] | null>(null);
  const [searching, setSearching] = useState(false);
  const [feeds, setFeeds] = useState<FeedWithUnread[] | null>(null);
  const [subscribedUrls, setSubscribedUrls] = useState<Set<string>>(new Set());
  const [urlValue, setUrlValue] = useState("");
  const [urlPreview, setUrlPreview] = useState<FeedSuggestion | null>(null);
  const [urlBusy, setUrlBusy] = useState(false);
  const [subscribingUrl, setSubscribingUrl] = useState<string | null>(null);

  const suggestionTokenRef = useRef(0);
  const searchTokenRef = useRef(0);
  const searchTimerRef = useRef<number | null>(null);

  const fetchFeeds = useCallback(async () => {
    try {
      const response = await feedsApi.list();
      setFeeds(response.feeds);
      setSubscribedUrls(new Set(response.feeds.map((feed) => normalizeFeedUrl(feed.url))));
    } catch {
      return;
    }
  }, []);

  const loadSuggestions = useCallback(
    async (categoryId: string) => {
      const token = ++suggestionTokenRef.current;
      setSuggestionStatus("loading");
      try {
        const response = await discoveryApi.discover({ categories: categoryId || undefined, limit: 24 });
        if (token !== suggestionTokenRef.current) return;
        setSuggestions(response.data);
        setSuggestionStatus("ready");
        setSuggestionError("");
      } catch (error) {
        if (token !== suggestionTokenRef.current) return;
        setSuggestionStatus("error");
        setSuggestionError(error instanceof Error ? error.message : "Unable to load suggestions");
      }
    },
    [],
  );

  useEffect(() => {
    if (sessionStatus !== "authenticated") return;
    void (async () => {
      try {
        const [categoriesResponse] = await Promise.all([discoveryApi.categories(), fetchFeeds()]);
        setCategories(categoriesResponse.data);
      } catch {
        setCategories([]);
      }
    })();
  }, [sessionStatus, fetchFeeds]);

  useEffect(() => {
    if (sessionStatus !== "authenticated") return;
    void loadSuggestions(selectedCategory);
  }, [sessionStatus, selectedCategory, loadSuggestions]);

  useEffect(() => {
    if (searchTimerRef.current !== null) {
      clearTimeout(searchTimerRef.current);
      searchTimerRef.current = null;
    }
    const trimmed = searchText.trim();
    if (trimmed.length < 2) {
      setSearchResults(null);
      setSearching(false);
      return;
    }
    setSearching(true);
    searchTimerRef.current = window.setTimeout(async () => {
      const token = ++searchTokenRef.current;
      try {
        const response = await discoveryApi.search(trimmed, { limit: 24 });
        if (token !== searchTokenRef.current) return;
        setSearchResults(response.data);
      } catch {
        if (token !== searchTokenRef.current) return;
        setSearchResults([]);
      } finally {
        if (token === searchTokenRef.current) setSearching(false);
      }
    }, SEARCH_DEBOUNCE_MS);
    return () => {
      if (searchTimerRef.current !== null) {
        clearTimeout(searchTimerRef.current);
        searchTimerRef.current = null;
      }
    };
  }, [searchText]);

  const isSubscribed = (url: string) => subscribedUrls.has(normalizeFeedUrl(url));

  const subscribe = async (target: FeedSuggestion) => {
    if (isSubscribed(target.url) || subscribingUrl) {
      if (isSubscribed(target.url)) {
        showToast({ title: "Already subscribed", message: target.title, kind: "info" });
      }
      return;
    }
    setSubscribingUrl(target.url);
    try {
      const { feed } = await feedsApi.create({ url: target.url });
      setSubscribedUrls((current) => new Set(current).add(normalizeFeedUrl(target.url)));
      showToast({
        title: `Subscribed to ${feed.title || target.title}`,
        message: "Articles will appear on Home shortly.",
        kind: "success",
      });
      if (urlPreview && normalizeFeedUrl(urlPreview.url) === normalizeFeedUrl(target.url)) {
        setUrlPreview(null);
        setUrlValue("");
      }
      void fetchFeeds();
    } catch (error) {
      if (error instanceof ApiError && error.status === 409) {
        setSubscribedUrls((current) => new Set(current).add(normalizeFeedUrl(target.url)));
        showToast({ title: "Already subscribed", message: target.title, kind: "info" });
      } else {
        showToast({
          title: "Could not subscribe",
          message: error instanceof Error ? error.message : undefined,
          kind: "error",
        });
      }
    } finally {
      setSubscribingUrl(null);
    }
  };

  const onSubmitUrl = async (event: JSX.TargetedEvent<HTMLFormElement, Event>) => {
    event.preventDefault();
    const trimmed = urlValue.trim();
    if (!trimmed || urlBusy) return;
    setUrlBusy(true);
    setUrlPreview(null);
    try {
      const response = await discoveryApi.validate(trimmed);
      if (!response.data.valid) {
        showToast({ title: "Not a valid feed", message: response.data.error || "The URL could not be parsed as an RSS or Atom feed.", kind: "error" });
      } else {
        setUrlPreview({
          url: trimmed,
          title: response.data.metadata?.title || trimmed,
          description: response.data.metadata?.description || undefined,
          favicon: response.data.metadata?.favicon || undefined,
          category: response.data.metadata?.category || undefined,
        });
      }
    } catch (error) {
      showToast({ title: "Validation failed", message: error instanceof Error ? error.message : undefined, kind: "error" });
    } finally {
      setUrlBusy(false);
    }
  };

  const displayed = searchResults ?? suggestions;
  const listHeading = searchResults !== null ? `Results for "${searchText.trim()}"` : selectedCategory ? categoryLabel(categories, selectedCategory) : "Popular feeds";

  return (
    <AppShell title="Discover">
      <div class="page">
        <div class="discover-add glass-card">
          <form class="discover-add-form" onSubmit={(event) => void onSubmitUrl(event)}>
            <div class="input-wrap">
              <LinkIcon size={16} />
              <input
                class="input"
                type="url"
                value={urlValue}
                onInput={(event) => setUrlValue(event.currentTarget.value)}
                placeholder="Add a feed by URL (https://example.com/feed.xml)"
                aria-label="Feed URL"
              />
            </div>
            <button type="submit" class="btn btn-primary btn-sm" disabled={!urlValue.trim() || urlBusy}>
              {urlBusy ? <span class="spinner" /> : null}
              {urlBusy ? "Checking" : "Validate"}
            </button>
          </form>
          {urlPreview ? (
            <div class="discover-preview">
              <FeedAvatar src={urlPreview.favicon} name={urlPreview.title} />
              <div class="discover-preview-body">
                <span class="discover-preview-title">{urlPreview.title}</span>
                {urlPreview.description ? <span class="discover-preview-desc">{urlPreview.description}</span> : null}
              </div>
              <button
                type="button"
                class="btn btn-primary btn-sm"
                onClick={() => void subscribe(urlPreview)}
                disabled={subscribingUrl !== null || isSubscribed(urlPreview.url)}
              >
                {subscribingUrl === urlPreview.url ? <span class="spinner" /> : <CheckIcon size={15} />}
                {isSubscribed(urlPreview.url) ? "Subscribed" : "Subscribe"}
              </button>
            </div>
          ) : null}
        </div>

        <div class="input-wrap">
          <SearchIcon size={16} />
          <input
            class="input"
            type="search"
            value={searchText}
            onInput={(event) => setSearchText(event.currentTarget.value)}
            placeholder="Search the feed catalog..."
            aria-label="Search the feed catalog"
            autocomplete="off"
          />
        </div>

        {searchResults === null && categories && categories.length > 0 ? (
          <div class="discover-filters">
            <button
              type="button"
              class={`chip${selectedCategory === "" ? " chip-active" : ""}`}
              onClick={() => setSelectedCategory("")}
            >
              All
            </button>
            {categories.map((category) => (
              <button
                key={category.id}
                type="button"
                class={`chip${selectedCategory === category.id ? " chip-active" : ""}`}
                onClick={() => setSelectedCategory(category.id)}
              >
                {category.name}
              </button>
            ))}
          </div>
        ) : null}

        {searchResults !== null ? (
          <span class="list-meta">{listHeading}</span>
        ) : null}

        {searching ? (
          <SkeletonList rows={4} />
        ) : searchResults === null && suggestionStatus === "loading" ? (
          <SkeletonList rows={5} />
        ) : searchResults === null && suggestionStatus === "error" ? (
          <ErrorState title="Failed to load suggestions" message={suggestionError} onRetry={() => void loadSuggestions(selectedCategory)} />
        ) : displayed.length === 0 ? (
          <EmptyState
            icon={<CompassIcon size={24} />}
            title={searchResults !== null ? "No feeds found" : "No feeds in this category"}
            description={
              searchResults !== null
                ? "Try a different search term, or add the feed by URL above."
                : "Pick another category, search the catalog, or add a feed by URL above."
            }
          />
        ) : (
          <div class="article-list">
            {displayed.map((suggestion) => {
              const subscribed = isSubscribed(suggestion.url);
              return (
                <div key={suggestion.url} class="discover-card glass-card">
                  <FeedAvatar src={suggestion.favicon} name={suggestion.title} />
                  <div class="discover-card-body">
                    <div class="discover-card-title-row">
                      <span class="discover-card-title">{suggestion.title}</span>
                      {subscribed ? (
                        <span class="discover-subscribed">
                          <CheckIcon size={13} />
                          Subscribed
                        </span>
                      ) : null}
                    </div>
                    {suggestion.description ? <span class="discover-card-desc">{suggestion.description}</span> : null}
                    <div class="discover-card-meta">
                      {suggestion.category ? <span class="chip">{suggestion.category}</span> : null}
                      <span>{shortUrl(suggestion.url)}</span>
                    </div>
                  </div>
                  <div class="discover-card-actions">
                    <button
                      type="button"
                      class={`btn btn-sm ${subscribed ? "btn-secondary" : "btn-primary"}`}
                      onClick={() => void subscribe(suggestion)}
                      disabled={subscribed || subscribingUrl !== null}
                    >
                      {subscribingUrl === suggestion.url ? <span class="spinner" /> : null}
                      {subscribed ? "Subscribed" : "Subscribe"}
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </AppShell>
  );
}

function categoryLabel(categories: DiscoveryCategory[] | null, id: string): string {
  return categories?.find((category) => category.id === id)?.name ?? "Feeds";
}

function shortUrl(url: string): string {
  try {
    const parsed = new URL(url);
    return parsed.hostname.replace(/^www\./, "");
  } catch {
    return url;
  }
}
