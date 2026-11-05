-- Idempotent. Safe to run more than once, including when some of these columns already exist.
-- Apply this on the live database BEFORE the next deploy, then run `npm run check:columns`.
-- This file does not touch production by itself.
--
-- A routine that fails every firing used to look the same as one that succeeded, because
-- next_run_at moved either way. These columns record the outcome. After three failures in a
-- row the app sets enabled = false and tells the person. enabled is created here as well so
-- this file is enough on its own if the provenance migration has not been applied yet.

alter table routines add column if not exists last_run_status text;
alter table routines add column if not exists last_run_error text;
alter table routines add column if not exists consecutive_failures integer not null default 0;
alter table routines add column if not exists enabled boolean not null default true;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'routines_last_run_status_check'
  ) then
    alter table routines
      add constraint routines_last_run_status_check
      check (last_run_status is null or last_run_status in ('success', 'failed'));
  end if;
end $$;
