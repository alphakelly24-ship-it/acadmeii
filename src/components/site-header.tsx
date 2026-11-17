"use client";

import type { User } from "@supabase/supabase-js";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { BrandMark } from "@/components/brand-mark";
import { createClient } from "@/lib/supabase/client";

export type SiteHeaderUser = {
  displayName: string;
  email: string | null;
};

function toHeaderUser(user: User): SiteHeaderUser {
  const metadataName = user.user_metadata?.display_name;
  const displayName = typeof metadataName === "string" ? metadataName.trim() : "";

  return {
    displayName: displayName || user.email || "Learner",
    email: user.email ?? null,
  };
}

type SiteHeaderProps = {
  initialUser: SiteHeaderUser | null;
};

export function SiteHeader({ initialUser }: SiteHeaderProps) {
  const router = useRouter();
  const [menuOpen, setMenuOpen] = useState(false);
  const [user, setUser] = useState(initialUser);
  const [isSigningOut, setIsSigningOut] = useState(false);
  const [signOutError, setSignOutError] = useState("");
  const hasSupabaseConfig = Boolean(
    process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  );
  const closeMenu = () => setMenuOpen(false);

  useEffect(() => {
    if (!hasSupabaseConfig) {
      return;
    }

    let mounted = true;

    try {
      const supabase = createClient();
      const {
        data: { subscription },
      } = supabase.auth.onAuthStateChange((event, session) => {
        if (!mounted || event === "INITIAL_SESSION") {
          return;
        }

        setUser(session?.user ? toHeaderUser(session.user) : null);
        setSignOutError("");
      });

      return () => {
        mounted = false;
        subscription.unsubscribe();
      };
    } catch {
      return;
    }
  }, [hasSupabaseConfig]);

  async function handleSignOut() {
    setIsSigningOut(true);
    setSignOutError("");

    try {
      const { error } = await createClient().auth.signOut();

      if (error) {
        setSignOutError("We could not sign you out. Please try again.");
        return;
      }

      setUser(null);
      closeMenu();
      router.replace("/");
      router.refresh();
    } catch {
      setSignOutError("We could not sign you out. Please try again.");
    } finally {
      setIsSigningOut(false);
    }
  }

  return (
    <header className="site-header">
      <div className="page-shell header-inner">
        <Link className="brand-lockup" href="/" aria-label="Academi home" onClick={closeMenu}>
          <BrandMark />
          <span className="brand-wordmark">academi</span>
        </Link>

        <nav
          id="primary-navigation"
          className="nav-links"
          aria-label="Main navigation"
          data-open={menuOpen}
        >
          <Link href="/courses" onClick={closeMenu}>Explore courses</Link>
          <Link href="/#approach" onClick={closeMenu}>Our approach</Link>

          {user ? (
            <div className="mobile-account-actions">
              <span className="mobile-account-label" title={user.email ?? user.displayName}>
                Signed in as <strong>{user.displayName}</strong>
              </span>
              {signOutError && (
                <span className="mobile-auth-error" role="alert">{signOutError}</span>
              )}
              <button
                className="header-signout"
                disabled={isSigningOut}
                onClick={() => void handleSignOut()}
                type="button"
              >
                {isSigningOut ? "Signing out…" : "Sign Out"}
              </button>
            </div>
          ) : (
            <div className="mobile-auth-actions">
              <Link className="button-link button-outline" href="/auth/signin" onClick={closeMenu}>
                Sign In
              </Link>
              <Link className="button-link button-solid" href="/auth/signup" onClick={closeMenu}>
                Sign Up
              </Link>
            </div>
          )}
        </nav>

        <div className="header-actions">
          <Link className="button-link button-solid browse-courses" href="/courses">
            Browse courses <span aria-hidden="true">↗</span>
          </Link>

          {user ? (
            <div className="header-account-actions">
              <span className="header-user-display" title={user.email ?? user.displayName}>
                {user.displayName}
              </span>
              <button
                className="header-signout"
                disabled={isSigningOut}
                onClick={() => void handleSignOut()}
                type="button"
              >
                {isSigningOut ? "Signing out…" : "Sign Out"}
              </button>
              {signOutError && (
                <span className="header-auth-error" role="alert">{signOutError}</span>
              )}
            </div>
          ) : (
            <div className="header-auth-actions">
              <Link className="button-link button-outline" href="/auth/signin">
                Sign In
              </Link>
              <Link className="button-link button-solid" href="/auth/signup">
                Sign Up
              </Link>
            </div>
          )}

          <button
            className="menu-toggle"
            type="button"
            aria-label={menuOpen ? "Close navigation menu" : "Open navigation menu"}
            aria-expanded={menuOpen}
            aria-controls="primary-navigation"
            onClick={() => setMenuOpen((open) => !open)}
          >
            <span aria-hidden="true">{menuOpen ? "×" : "☰"}</span>
          </button>
        </div>
      </div>
    </header>
  );
}
