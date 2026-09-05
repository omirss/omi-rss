import { useEffect, useRef } from "preact/hooks";
import type { ComponentChildren } from "preact";
import { useLocation } from "@neutron-build/core/client";

export function PageTransition({ children }: { children: ComponentChildren }) {
  const { pathname } = useLocation();
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const scroller = ref.current?.closest(".shell-content");
    if (scroller) scroller.scrollTop = 0;
  }, []);

  return (
    <div ref={ref} key={pathname} class="page-enter">
      {children}
    </div>
  );
}
