begin;
select * from no_plan();

select is(public.plant_scan_take('u1', 2), true, 'the first check is allowed');
select is(public.plant_scan_take('u1', 2), true, 'and the second');
select is(public.plant_scan_take('u1', 2), false, 'the third is over the daily limit');
select is(public.plant_scan_take('u1', 2), false, 'and stays refused');
select is((select n from public.plant_scans where uid = 'u1'), 2, 'the counter does not run past the limit');
select is(public.plant_scan_take('u2', 2), true, 'another person has their own allowance');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"u3","role":"authenticated"}', true);
select throws_ok($f$select public.plant_scan_take('u3', 99)$f$, '42501', null, 'a signed-in person cannot call it directly');
select is((select count(*)::int from public.plant_scans), 0, 'and cannot read the counters');

select * from finish();
rollback;
