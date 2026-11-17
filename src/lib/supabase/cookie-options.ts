const usePlainHttpLocalCookies =
  process.env.NEXT_PUBLIC_SUPABASE_COOKIE_MODE === "local-http";

// Cloud Preview is HTTPS inside a cross-site iframe, so its auth cookie must be
// SameSite=None; Secure. Plain-HTTP local testing is an explicit opt-in and is
// never inferred from NODE_ENV or the development server's internal request.
export const supabaseCookieOptions = usePlainHttpLocalCookies
  ? { sameSite: "lax" as const, secure: false }
  : { sameSite: "none" as const, secure: true };
