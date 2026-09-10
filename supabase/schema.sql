-- ==============================================================================
-- Persistent 2D Simulated World: Garden Persistence Schema
-- ==============================================================================
-- Run this script in the Supabase SQL Editor (Dashboard -> SQL Editor -> New Query)

-- 1. Table: garden_state
-- Stores the single-source-of-truth snapshot of the persistent garden.
create table if not exists public.garden_state (
    id text primary key default 'main_garden',
    total_plants integer not null default 0,
    last_planted_at timestamptz,
    last_saved_at timestamptz not null default now(),
    planting_interval_seconds integer not null default 600,
    max_plots integer not null default 12,
    active_plots jsonb not null default '[]'::jsonb,
    updated_at timestamptz not null default now()
);

-- 2. Table: garden_events
-- Stores chronological planting and simulation events (both live and reconstructed offline).
create table if not exists public.garden_events (
    id bigint generated always as identity primary key,
    world_id text not null default 'main_garden',
    plant_number integer not null,
    plot_index integer not null,
    event_time timestamptz not null default now(),
    event_time_str text not null,
    message text not null,
    is_offline boolean not null default false,
    created_at timestamptz not null default now()
);

-- 3. Initial Default State
insert into public.garden_state (id, total_plants, last_planted_at, last_saved_at, planting_interval_seconds, max_plots, active_plots)
values ('main_garden', 0, now(), now(), 600, 12, '[]'::jsonb)
on conflict (id) do nothing;

-- 4. Row Level Security (RLS)
alter table public.garden_state enable row level security;
alter table public.garden_events enable row level security;

-- 5. Open Policies for Anon Key (Permits read/write for standalone client simulation)
drop policy if exists "Allow anon full access on garden_state" on public.garden_state;
create policy "Allow anon full access on garden_state"
    on public.garden_state
    for all
    to anon
    using (true)
    with check (true);

drop policy if exists "Allow anon full access on garden_events" on public.garden_events;
create policy "Allow anon full access on garden_events"
    on public.garden_events
    for all
    to anon
    using (true)
    with check (true);

-- End of schema
