import type { ErrorBoundaryProps } from "@neutron-build/core";
import { ThemeProvider } from "../lib/theme.js";
import { SessionProvider } from "../lib/auth.js";
import { ToastProvider } from "../components/Toast.js";
import "../styles/theme.css";

const THEME_BOOT_SCRIPT = `(function(){
var PRESETS=["glass","glass_light","aurora","ember","mono"];
var p=null,m=null;
try{p=localStorage.getItem("omi.theme.preset");m=localStorage.getItem("omi.theme.mode");}catch(e){}
if(!p||!m){
var match=document.cookie.match(/(?:^|; )omi_theme=([^;]*)/);
if(match){
var parts=decodeURIComponent(match[1]).split(":");
if(!p&&PRESETS.indexOf(parts[0])>=0)p=parts[0];
if(!m&&(parts[1]==="system"||parts[1]==="light"||parts[1]==="dark"))m=parts[1];
}
}
if(PRESETS.indexOf(p)<0)p="glass";
if(m!=="system"&&m!=="light"&&m!=="dark")m="system";
var r=m;
if(r==="system"){r="dark";try{r=window.matchMedia("(prefers-color-scheme: light)").matches?"light":"dark";}catch(e){}}
var el=document.documentElement;
el.setAttribute("data-preset",p);
el.setAttribute("data-mode",r);
})();`;

export function head() {
  return {
    title: "Omi RSS",
    description: "Omi RSS reader",
    headScripts: [{ id: "omi-theme-boot", content: THEME_BOOT_SCRIPT }],
    link: [
      { rel: "manifest", href: "/manifest.webmanifest" },
      { rel: "apple-touch-icon", href: "/apple-touch-icon.png" },
    ],
  };
}

export default function Layout({ children }: { children: preact.ComponentChildren }) {
  return (
    <ThemeProvider>
      <SessionProvider>
        <ToastProvider>
          <div class="app-root">{children}</div>
        </ToastProvider>
      </SessionProvider>
    </ThemeProvider>
  );
}

export function ErrorBoundary({ error }: ErrorBoundaryProps) {
  return (
    <div class="auth-screen">
      <div class="glass-panel auth-card">
        <div class="auth-brand">
          <span class="auth-logo">!</span>
          <h1 class="auth-title">Something went wrong</h1>
          <p class="auth-subtitle">{error.message}</p>
        </div>
        <a class="btn btn-primary auth-submit" href="/">
          Go home
        </a>
      </div>
    </div>
  );
}
