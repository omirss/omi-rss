import type { ErrorBoundaryProps } from "@neutron-build/core";

export default function Layout({ children }: { children: preact.ComponentChildren }) {
  return <main>{children}</main>;
}

export function ErrorBoundary({ error }: ErrorBoundaryProps) {
  return (
    <main>
      <h1>Something went wrong</h1>
      <p>{error.message}</p>
      <p>
        <a href="/">Go home</a>
      </p>
    </main>
  );
}
