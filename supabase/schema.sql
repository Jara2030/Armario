-- =====================================================================
-- Armario · esquema de Supabase
--
-- Cómo usarlo: Supabase → tu proyecto → SQL Editor → New query →
-- pega TODO este archivo → Run. Se puede ejecutar varias veces sin romper
-- nada (no borra datos).
--
-- Qué crea:
--   * 3 tablas (items, outfits, wear_logs) con Row Level Security: cada
--     usuario solo puede ver y tocar SUS filas.
--   * Un bucket privado "photos" donde cada usuario solo accede a su carpeta.
-- =====================================================================

-- ---------------------------------------------------------------- tablas

create table if not exists public.items (
  id text primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null default '',
  type text not null default 'otro',
  colors jsonb not null default '[]'::jsonb,
  seasons jsonb not null default '[]'::jsonb,
  occasions jsonb not null default '[]'::jsonb,
  brand text not null default '',
  notes text not null default '',
  status text not null default 'disponible',
  photo_version bigint,
  created_at bigint not null,
  updated_at bigint not null,          -- reloj del dispositivo (ms)
  deleted boolean not null default false,
  server_updated_at timestamptz not null default clock_timestamp()
);

create table if not exists public.outfits (
  id text primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null default '',
  notes text not null default '',
  item_ids jsonb not null default '[]'::jsonb,
  created_at bigint not null,
  updated_at bigint not null,
  deleted boolean not null default false,
  server_updated_at timestamptz not null default clock_timestamp()
);

create table if not exists public.wear_logs (
  id text primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  item_id text not null,
  outfit_id text,
  worn_on text not null,               -- AAAA-MM-DD
  created_at bigint not null,
  updated_at bigint not null,
  deleted boolean not null default false,
  server_updated_at timestamptz not null default clock_timestamp()
);

create index if not exists items_sync_idx on public.items (user_id, server_updated_at, id);
create index if not exists outfits_sync_idx on public.outfits (user_id, server_updated_at, id);
create index if not exists wear_logs_sync_idx on public.wear_logs (user_id, server_updated_at, id);

-- ------------------------------------------------- disparador de sincronía
-- En cada escritura:
--   * si llega una versión MÁS ANTIGUA que la guardada, se ignora
--     (gana siempre la modificación más reciente);
--   * se apunta la hora del servidor, que es lo que usan los dispositivos
--     para pedir "lo que ha cambiado desde la última vez";
--   * el dueño de la fila no se puede cambiar.

create or replace function public.armario_touch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.updated_at < old.updated_at then
      return old;
    end if;
    new.user_id := old.user_id;
  end if;
  new.server_updated_at := clock_timestamp();
  return new;
end;
$$;

drop trigger if exists armario_touch on public.items;
create trigger armario_touch before insert or update on public.items
  for each row execute function public.armario_touch();

drop trigger if exists armario_touch on public.outfits;
create trigger armario_touch before insert or update on public.outfits
  for each row execute function public.armario_touch();

drop trigger if exists armario_touch on public.wear_logs;
create trigger armario_touch before insert or update on public.wear_logs
  for each row execute function public.armario_touch();

-- ---------------------------------------------------- Row Level Security

alter table public.items enable row level security;
alter table public.outfits enable row level security;
alter table public.wear_logs enable row level security;

drop policy if exists "items: solo el dueño" on public.items;
create policy "items: solo el dueño" on public.items
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "outfits: solo el dueño" on public.outfits;
create policy "outfits: solo el dueño" on public.outfits
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "wear_logs: solo el dueño" on public.wear_logs;
create policy "wear_logs: solo el dueño" on public.wear_logs
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Nadie sin sesión iniciada puede hacer nada.
revoke all on public.items, public.outfits, public.wear_logs from anon;
grant select, insert, update, delete
  on public.items, public.outfits, public.wear_logs to authenticated;

-- ------------------------------------------------------- fotos (Storage)
-- Bucket PRIVADO. Límite de 1 MB por archivo y solo JPEG, como red de
-- seguridad para no gastar el 1 GB gratuito (la app sube ~150-250 KB).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', false, 1048576, array['image/jpeg'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Las fotos se guardan en  <id de usuario>/<id de prenda>.jpg
-- y cada usuario solo puede acceder a su propia carpeta.

drop policy if exists "photos: leer las mías" on storage.objects;
create policy "photos: leer las mías" on storage.objects
  for select to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "photos: subir las mías" on storage.objects;
create policy "photos: subir las mías" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "photos: actualizar las mías" on storage.objects;
create policy "photos: actualizar las mías" on storage.objects
  for update to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "photos: borrar las mías" on storage.objects;
create policy "photos: borrar las mías" on storage.objects
  for delete to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
