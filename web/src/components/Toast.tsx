import { createContext } from "preact";
import { useCallback, useContext, useEffect, useMemo, useRef, useState } from "preact/hooks";
import type { ComponentChildren, VNode } from "preact";
import { CheckCircleIcon, CloseIcon, ErrorCircleIcon, InfoIcon } from "./Icons.js";

export type ToastKind = "info" | "success" | "error";

export interface ToastOptions {
  title: string;
  message?: string;
  kind?: ToastKind;
  durationMs?: number;
}

interface ToastEntry extends Required<Pick<ToastOptions, "title" | "kind">> {
  id: number;
  message?: string;
}

interface ToastContextValue {
  showToast: (options: ToastOptions) => number;
}

const ToastContext = createContext<ToastContextValue | null>(null);

const kindIcons: Record<ToastKind, VNode> = {
  info: <InfoIcon size={18} />,
  success: <CheckCircleIcon size={18} />,
  error: <ErrorCircleIcon size={18} />,
};

export function ToastProvider({ children }: { children: ComponentChildren }) {
  const [toasts, setToasts] = useState<ToastEntry[]>([]);
  const nextId = useRef(1);

  const dismiss = useCallback((id: number) => {
    setToasts((current) => current.filter((toast) => toast.id !== id));
  }, []);

  const showToast = useCallback((options: ToastOptions) => {
    const id = nextId.current++;
    const entry: ToastEntry = {
      id,
      title: options.title,
      kind: options.kind ?? "info",
      message: options.message,
    };
    setToasts((current) => [...current, entry]);
    return id;
  }, []);

  const value = useMemo<ToastContextValue>(() => ({ showToast }), [showToast]);

  return (
    <ToastContext.Provider value={value}>
      {children}
      <div class="toast-host" role="status" aria-live="polite">
        {toasts.map((toast) => (
          <ToastRow key={toast.id} toast={toast} dismiss={dismiss} />
        ))}
      </div>
    </ToastContext.Provider>
  );
}

function ToastRow({ toast, dismiss }: { toast: ToastEntry; dismiss: (id: number) => void }) {
  const duration = toast.kind === "error" ? 6000 : 4000;

  useEffect(() => {
    const timer = setTimeout(() => dismiss(toast.id), duration);
    return () => clearTimeout(timer);
  }, [toast.id, duration, dismiss]);

  return (
    <div class={`toast glass-panel toast-${toast.kind}`}>
      <span class="toast-icon">{kindIcons[toast.kind]}</span>
      <div class="toast-body">
        <div class="toast-title">{toast.title}</div>
        {toast.message ? <div class="toast-message">{toast.message}</div> : null}
      </div>
      <button type="button" class="toast-close" onClick={() => dismiss(toast.id)} aria-label="Dismiss notification">
        <CloseIcon size={14} />
      </button>
    </div>
  );
}

export function useToast(): ToastContextValue {
  const context = useContext(ToastContext);
  if (!context) {
    throw new Error("useToast must be used within ToastProvider");
  }
  return context;
}
