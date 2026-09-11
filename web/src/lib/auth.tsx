import { createContext } from "preact";
import { useContext, useEffect, useMemo, useState } from "preact/hooks";
import { SESSION_EXPIRED_EVENT, authApi, tokenStore, usersApi } from "./client.js";
import type { UserDetail, UserProfile } from "./api-types.js";

export type SessionStatus = "loading" | "authenticated" | "anonymous";

interface SessionContextValue {
  status: SessionStatus;
  user: UserProfile | null;
  login: (emailOrUsername: string, password: string) => Promise<void>;
  register: (input: { email?: string | null; username: string; password: string; firstName?: string; lastName?: string }) => Promise<void>;
  logout: () => Promise<void>;
  refreshUser: () => Promise<void>;
}

const SessionContext = createContext<SessionContextValue | null>(null);

function toProfile(detail: UserDetail): UserProfile {
  return {
    id: detail.id,
    email: detail.email,
    username: detail.username,
    firstName: detail.firstName,
    lastName: detail.lastName,
    avatarUrl: detail.avatarUrl,
    role: detail.role,
    emailVerified: detail.emailVerified,
    settings: detail.settings,
  };
}

export function SessionProvider({ children }: { children: preact.ComponentChildren }) {
  const [status, setStatus] = useState<SessionStatus>("loading");
  const [user, setUser] = useState<UserProfile | null>(null);

  useEffect(() => {
    const tokens = tokenStore.getTokens();
    if (!tokens) {
      setStatus("anonymous");
      return;
    }
    setUser(tokenStore.getUser());
    setStatus("authenticated");
    usersApi
      .getMe()
      .then(({ user: detail }) => {
        const profile = toProfile(detail);
        tokenStore.setUser(profile);
        setUser(profile);
      })
      .catch(() => undefined);
  }, []);

  useEffect(() => {
    const onExpired = () => {
      setStatus("anonymous");
      setUser(null);
    };
    addEventListener(SESSION_EXPIRED_EVENT, onExpired);
    return () => removeEventListener(SESSION_EXPIRED_EVENT, onExpired);
  }, []);

  const value = useMemo<SessionContextValue>(() => ({
    status,
    user,
    async login(emailOrUsername, password) {
      const response = await authApi.login({ emailOrUsername, password });
      tokenStore.rotateSession();
      tokenStore.setTokens({ token: response.token, refreshToken: response.refreshToken });
      tokenStore.setUser(response.user);
      setUser(response.user);
      setStatus("authenticated");
    },
    async register(input) {
      const response = await authApi.register(input);
      tokenStore.rotateSession();
      tokenStore.setTokens({ token: response.token, refreshToken: response.refreshToken });
      setStatus("authenticated");
      const { user: detail } = await usersApi.getMe();
      const profile = toProfile(detail);
      tokenStore.setUser(profile);
      setUser(profile);
    },
    async logout() {
      // Revoke server-side FIRST while the tokens are still stored; the
      // local clear happens afterwards (and even on server failure).
      try {
        await authApi.logout();
      } finally {
        tokenStore.clear();
        setStatus("anonymous");
        setUser(null);
      }
    },
    async refreshUser() {
      const { user: detail } = await usersApi.getMe();
      const profile = toProfile(detail);
      tokenStore.setUser(profile);
      setUser(profile);
    },
  }), [status, user]);

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession(): SessionContextValue {
  const context = useContext(SessionContext);
  if (!context) {
    throw new Error("useSession must be used within SessionProvider");
  }
  return context;
}
