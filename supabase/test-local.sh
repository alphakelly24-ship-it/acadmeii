#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v supabase >/dev/null 2>&1; then
  echo "Supabase CLI is required. Install it using the official local-development guide:" >&2
  echo "https://supabase.com/docs/guides/local-development" >&2
  exit 127
fi

if grep -Eq '^schemas[[:space:]]*=.*"private"' supabase/config.toml; then
  echo "Refusing to run: the private schema must not be listed in [api].schemas." >&2
  exit 1
fi

echo "Starting the local Supabase stack (no hosted project is linked or contacted)."
supabase start

echo "Resetting the local database and applying local migrations. This deletes local database data."
supabase db reset --local

echo "Running the local pgTAP database tests."
supabase test db
