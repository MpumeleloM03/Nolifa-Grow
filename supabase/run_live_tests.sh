#!/bin/sh
# Runs the real-database tests against the local Supabase (start it first with `supabase start`).
cd "$(dirname "$0")/.." || exit 1
SB=${SUPABASE_CLI:-supabase}
ENV=$($SB status -o env 2>/dev/null)
export SUPABASE_URL=$(echo "$ENV" | grep '^API_URL' | cut -d= -f2 | tr -d '"')
export SUPABASE_ANON_KEY=$(echo "$ENV" | grep '^ANON_KEY' | cut -d= -f2 | tr -d '"')
export SUPABASE_SERVICE_KEY=$(echo "$ENV" | grep '^SERVICE_ROLE_KEY' | cut -d= -f2 | tr -d '"')
cd packages/ubuntu_core && flutter test test_live
