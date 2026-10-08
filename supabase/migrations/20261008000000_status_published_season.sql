-- Name the season the live revision covers.
--
-- `data_refresh_status.season` is the latest probe or build TARGET, so after
-- the October rollover it already says 2027 while the last published revision
-- (refresh_id, published_at, max_game_date, coverage) still describes 2025-26.
-- Clients had to infer that from max_game_date. `published_season` states it:
-- the hoopR season (named for the year it ends) containing max_game_date.
--
-- A target ahead of the published season with status 'source_pending' and
-- last_error_code 'season_pending' means "the new season's schedule is out but
-- its box scores are not": keep showing the published season.
--
-- Appended as the last column, so existing clients and the select=* contract
-- are unaffected.

create or replace view public.data_refresh_status as
select
  state.status,
  state.last_success_refresh_id as refresh_id,
  coalesce(state.current_refresh_id, state.last_attempt_refresh_id) as latest_refresh_id,
  state.last_success_refresh_id,
  state.last_success_fingerprint as source_fingerprint,
  state.latest_source_fingerprint,
  state.last_success_source_published_at as source_published_at,
  state.latest_source_published_at,
  state.last_success_published_at as published_at,
  state.last_checked_at,
  state.season,
  state.season_type,
  state.max_week,
  state.max_game_date,
  state.expected_games,
  state.observed_games,
  state.coverage_status,
  state.ngs_status,
  state.pfr_status,
  state.last_error_code,
  case
    when state.max_game_date is null then null
    else extract(year from state.max_game_date)::integer
         + case when extract(month from state.max_game_date) >= 10 then 1 else 0 end
  end as published_season
from public.data_refresh_state state
where state.singleton;

grant select on public.data_refresh_status to anon, authenticated, service_role;

notify pgrst, 'reload schema';
