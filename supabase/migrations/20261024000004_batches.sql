-- A driver takes a whole batch of jobs in one step. All of them or none.
create or replace function public.claim_batch(p_ids text[], p_name text) returns boolean
language plpgsql as $$
declare
  v_uid text := auth.uid()::text;
  n int;
begin
  if v_uid is null then raise exception 'sign in first' using errcode = '42501'; end if;
  if p_ids is null or cardinality(p_ids) = 0 or cardinality(p_ids) > 30 then
    raise exception 'A batch holds 1 to 30 jobs.';
  end if;
  perform 1 from public.market_orders where id = any (p_ids) order by id for update;
  select count(*) into n from public.market_orders
   where id = any (p_ids)
     and data ->> 'status' = 'findingDriver'
     and public.jnull(data, 'driverId')
     and (data ->> 'hubStage' is null or data ->> 'hubStage' = 'released');
  if n <> cardinality(p_ids) then return false; end if;
  update public.market_orders
     set data = data || jsonb_build_object(
       'driverId', v_uid, 'driver', p_name, 'status', 'assigned',
       'rev', coalesce((data ->> 'rev')::int, 0) + 1,
       'participants', coalesce(data -> 'participants', '[]'::jsonb) || to_jsonb(v_uid))
   where id = any (p_ids);
  return true;
end $$;
