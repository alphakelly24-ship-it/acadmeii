import type { Metadata } from "next";
import type { ReactNode } from "react";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader, type SiteHeaderUser } from "@/components/site-header";
import { createClient as createSupabaseServerClient } from "@/lib/supabase/server";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "Academi — Learn with purpose",
    template: "%s — Academi",
  },
  description:
    "A thoughtful starting point for practical online learning. Explore Academi's sample course catalog.",
};

async function getInitialHeaderUser(): Promise<SiteHeaderUser | null> {
  if (!process.env.NEXT_PUBLIC_SUPABASE_URL || !process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY) {
    return null;
  }

  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.auth.getUser();

    if (error || !data.user) {
      return null;
    }

    const metadataName = data.user.user_metadata?.display_name;
    const displayName = typeof metadataName === "string" ? metadataName.trim() : "";

    return {
      displayName: displayName || data.user.email || "Learner",
      email: data.user.email ?? null,
    };
  } catch {
    // Keep public pages available if the optional auth service is not reachable.
    return null;
  }
}

export default async function RootLayout({ children }: Readonly<{ children: ReactNode }>) {
  const initialUser = await getInitialHeaderUser();

  return (
    <html lang="en">
      <body className="min-h-screen antialiased">
        <a className="skip-link" href="#main-content">
          Skip to content
        </a>
        <SiteHeader initialUser={initialUser} />
        {children}
        <SiteFooter />
      </body>
    </html>
  );
}
