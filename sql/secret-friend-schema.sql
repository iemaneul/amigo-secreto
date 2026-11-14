create extension if not exists pgcrypto;

create table if not exists public.participants (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete cascade,
  username text not null unique,
  phone_number text not null unique,
  password_hash text,
  display_name text not null,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.participants
  add column if not exists phone_number text;
alter table public.participants
  add column if not exists password_hash text;

create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  participant_id uuid not null unique references public.participants(id) on delete cascade,
  favorite_color text,
  hobbies text,
  favorite_foods text,
  favorite_movies text,
  favorite_games text,
  likes text,
  dislikes text,
  gift_suggestions text,
  notes text,
  updated_at timestamptz not null default now()
);

create table if not exists public.draw_results (
  id uuid primary key default gen_random_uuid(),
  giver_id uuid not null references public.participants(id) on delete cascade,
  receiver_id uuid not null references public.participants(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (giver_id, receiver_id)
);

create table if not exists public.draw_settings (
  id uuid primary key default '11111111-1111-4111-8111-111111111111'::uuid,
  draw_completed boolean not null default false,
  draw_locked boolean not null default false,
  rules jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.draw_restrictions (
  id uuid primary key default gen_random_uuid(),
  giver_id uuid not null references public.participants(id) on delete cascade,
  disallowed_id uuid not null references public.participants(id) on delete cascade,
  unique (giver_id, disallowed_id),
  check (giver_id <> disallowed_id)
);

create or replace function public.current_participant_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id
  from public.participants p
  where p.auth_user_id = auth.uid()
  limit 1;
$$;

create or replace function public.is_current_user_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.participants p
    where p.auth_user_id = auth.uid() and p.is_admin = true
  );
$$;

create or replace view public.participant_names as
select id, display_name
from public.participants;

revoke all on public.participant_names from public, anon;
grant select on public.participant_names to authenticated;

alter table public.participants enable row level security;
alter table public.profiles enable row level security;
alter table public.draw_results enable row level security;
alter table public.draw_settings enable row level security;
alter table public.draw_restrictions enable row level security;

drop policy if exists "participants_are_viewable_by_owner_or_admin" on public.participants;
drop policy if exists "participants_are_manageable_by_admin" on public.participants;
drop policy if exists "profiles_are_viewable_by_owner_or_receiver_friend" on public.profiles;
drop policy if exists "profiles_are_manageable_by_owner" on public.profiles;
drop policy if exists "profiles_are_updatable_by_owner" on public.profiles;
drop policy if exists "results_are_visible_to_participant_only" on public.draw_results;
drop policy if exists "results_are_visible_to_giver_only" on public.draw_results;
drop policy if exists "draw_settings_visible_to_authenticated_users" on public.draw_settings;
drop policy if exists "draw_settings_manageable_by_admin_only" on public.draw_settings;
drop policy if exists "draw_restrictions_manageable_by_admin_only" on public.draw_restrictions;

drop policy if exists "profiles_are_viewable_by_owner_or_receiver_friend" on public.profiles;
create policy "profiles_are_viewable_by_owner_or_receiver_friend"
on public.profiles
for select
using (
  participant_id = public.current_participant_id() or
  participant_id in (
    select dr.receiver_id
    from public.draw_results dr
    where dr.giver_id = public.current_participant_id()
  )
);

create policy "participants_are_viewable_by_owner_or_admin"
on public.participants
for select
using (
  auth.uid() = auth_user_id or public.is_current_user_admin()
);

create policy "participants_are_manageable_by_admin"
on public.participants
for update
using (public.is_current_user_admin())
with check (public.is_current_user_admin());

create policy "profiles_are_manageable_by_owner"
on public.profiles
for insert
with check (
  participant_id = public.current_participant_id()
);

create policy "profiles_are_updatable_by_owner"
on public.profiles
for update
using (
  participant_id = public.current_participant_id()
)
with check (
  participant_id = public.current_participant_id()
);

create policy "results_are_visible_to_giver_only"
on public.draw_results
for select
using (giver_id = public.current_participant_id());

create policy "draw_settings_visible_to_authenticated_users"
on public.draw_settings
for select
using (auth.role() = 'authenticated');

create policy "draw_settings_manageable_by_admin_only"
on public.draw_settings
for update
using (public.is_current_user_admin())
with check (public.is_current_user_admin());

create policy "draw_restrictions_manageable_by_admin_only"
on public.draw_restrictions
for all
using (public.is_current_user_admin())
with check (public.is_current_user_admin());

insert into public.draw_settings (id, draw_completed, draw_locked, rules, updated_at)
values (
  '11111111-1111-4111-8111-111111111111'::uuid,
  false,
  false,
  '[{"giver":"emanuel","blocked":["eduardo","lorena"]},{"giver":"caio","blocked":["eduardo","lorena"]},{"giver":"thais","blocked":["eduardo","lorena"]}]'::jsonb,
  now()
)
on conflict (id) do nothing;

create or replace function public.participant_portal_login(p_phone text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  portal jsonb;
begin
  select jsonb_build_object(
    'participant', jsonb_build_object(
      'id', p.id,
      'display_name', p.display_name
    ),
    'draw_completed', coalesce(settings.draw_completed, false),
    'receiver', case
      when receiver.id is null then null
      else jsonb_build_object('id', receiver.id, 'display_name', receiver.display_name)
    end,
    'own_profile', case
      when own_profile.participant_id is null then '{}'::jsonb
      else to_jsonb(own_profile) - 'id' - 'participant_id' - 'updated_at'
    end,
    'receiver_profile', case
      when receiver_profile.participant_id is null then '{}'::jsonb
      else to_jsonb(receiver_profile) - 'id' - 'participant_id' - 'updated_at'
    end
  )
  into portal
  from public.participants p
  left join public.draw_settings settings
    on settings.id = '11111111-1111-4111-8111-111111111111'::uuid
  left join public.draw_results result
    on result.giver_id = p.id
  left join public.participants receiver
    on receiver.id = result.receiver_id
  left join public.profiles own_profile
    on own_profile.participant_id = p.id
  left join public.profiles receiver_profile
    on receiver_profile.participant_id = receiver.id
  where p.phone_number = regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g')
    and p.password_hash is not null
    and crypt(coalesce(p_password, ''), p.password_hash) = p.password_hash;

  return portal;
end;
$$;

create or replace function public.participant_profile_save(
  p_phone text,
  p_password text,
  p_profile jsonb
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  participant_id uuid;
begin
  select p.id
  into participant_id
  from public.participants p
  where p.phone_number = regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g')
    and p.password_hash is not null
    and crypt(coalesce(p_password, ''), p.password_hash) = p.password_hash;

  if participant_id is null then
    raise exception 'Credenciais inválidas.';
  end if;

  if p_profile is null or jsonb_typeof(p_profile) <> 'object' then
    raise exception 'Dados de perfil inválidos.';
  end if;

  insert into public.profiles (
    participant_id,
    favorite_color,
    hobbies,
    favorite_foods,
    favorite_movies,
    favorite_games,
    likes,
    dislikes,
    gift_suggestions,
    notes,
    updated_at
  )
  values (
    participant_id,
    nullif(p_profile ->> 'favorite_color', ''),
    nullif(p_profile ->> 'hobbies', ''),
    nullif(p_profile ->> 'favorite_foods', ''),
    nullif(p_profile ->> 'favorite_movies', ''),
    nullif(p_profile ->> 'favorite_games', ''),
    nullif(p_profile ->> 'likes', ''),
    nullif(p_profile ->> 'dislikes', ''),
    nullif(p_profile ->> 'gift_suggestions', ''),
    nullif(p_profile ->> 'notes', ''),
    now()
  )
  on conflict (participant_id) do update
  set favorite_color = excluded.favorite_color,
      hobbies = excluded.hobbies,
      favorite_foods = excluded.favorite_foods,
      favorite_movies = excluded.favorite_movies,
      favorite_games = excluded.favorite_games,
      likes = excluded.likes,
      dislikes = excluded.dislikes,
      gift_suggestions = excluded.gift_suggestions,
      notes = excluded.notes,
      updated_at = excluded.updated_at;

  return true;
end;
$$;

create or replace function public.run_secret_draw()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  givers uuid[];
  receivers uuid[];
  participant_count integer;
  attempt integer;
  idx integer;
  valid_assignment boolean;
  draw_already_completed boolean;
begin
  perform pg_advisory_xact_lock(hashtext('friend-secret-draw'));

  select coalesce(bool_or(draw_completed), false)
  into draw_already_completed
  from public.draw_settings
  where id = '11111111-1111-4111-8111-111111111111'::uuid;

  if draw_already_completed then
    raise exception 'O sorteio já foi realizado.';
  end if;

  select array_agg(id order by id), count(*)::integer
  into givers, participant_count
  from public.participants;

  if coalesce(participant_count, 0) <> 9 then
    raise exception 'O sorteio exige exatamente 9 participantes; encontrados: %.', coalesce(participant_count, 0);
  end if;

  for attempt in 1..10000 loop
    select array_agg(id order by random())
    into receivers
    from public.participants;

    valid_assignment := true;

    for idx in 1..participant_count loop
      if givers[idx] = receivers[idx]
        or exists (
          select 1
          from public.draw_restrictions restriction
          where restriction.giver_id = givers[idx]
            and restriction.disallowed_id = receivers[idx]
        )
      then
        valid_assignment := false;
        exit;
      end if;
    end loop;

    exit when valid_assignment;
  end loop;

  if not valid_assignment then
    raise exception 'Não foi encontrada uma combinação válida.';
  end if;

  delete from public.draw_results;

  for idx in 1..participant_count loop
    insert into public.draw_results (giver_id, receiver_id)
    values (givers[idx], receivers[idx]);
  end loop;

  insert into public.draw_settings (id, draw_completed, draw_locked, updated_at)
  values (
    '11111111-1111-4111-8111-111111111111'::uuid,
    true,
    true,
    now()
  )
  on conflict (id) do update
  set draw_completed = true,
      draw_locked = true,
      updated_at = now();
end;
$$;

revoke all on public.participants, public.profiles, public.draw_results,
  public.draw_settings, public.draw_restrictions, public.participant_names
  from public, anon, authenticated;
revoke create on schema public from public, anon, authenticated;

revoke all on function public.participant_portal_login(text, text) from public;
revoke all on function public.participant_profile_save(text, text, jsonb) from public;
revoke all on function public.run_secret_draw() from public, anon, authenticated;

grant execute on function public.participant_portal_login(text, text) to anon, authenticated;
grant execute on function public.participant_profile_save(text, text, jsonb) to anon, authenticated;
