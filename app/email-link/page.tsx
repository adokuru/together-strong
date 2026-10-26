"use client";
import { useSyncExternalStore } from "react";
import Link from "next/link";
import { ArrowRight, ShieldCheck } from "lucide-react";
export default function EmailLink() {
  const fragment = useSyncExternalStore(
    (callback) => {
      window.addEventListener("hashchange", callback);
      return () => window.removeEventListener("hashchange", callback);
    },
    () => location.hash,
    () => "",
  );
  let url: string | null = null;
  try {
    const value = new URLSearchParams(fragment.slice(1)).get("verify");
    if (value) {
      const parsed = new URL(value);
      if (
        parsed.origin === location.origin &&
        parsed.pathname === "/api/auth/magic-link/verify"
      )
        url = parsed.toString();
    }
  } catch {}
  return (
    <main className="auth-page">
      <section className="auth-card">
        <ShieldCheck size={35} className="auth-shield" />
        <div className="eyebrow">TOGETHER STRONG</div>
        <h1>Continue to your private space.</h1>
        <p>
          This extra click keeps email scanners from using your single-use link
          before you do.
        </p>
        {url ? (
          <a className="dark-button email-continue" href={url}>
            Verify email & continue <ArrowRight size={17} />
          </a>
        ) : (
          <p className="error-text" role="alert">
            This link is incomplete. Request a fresh setup link from the app.
          </p>
        )}
        <Link className="text-button" href="/">
          Back to profile choices
        </Link>
      </section>
    </main>
  );
}
