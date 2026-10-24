-- Live updates for the tables the first migration left out.
alter publication supabase_realtime add table
  public.cattle, public.health_log, public.users, public.chat_messages,
  public.water_prefs, public.market_profiles;
