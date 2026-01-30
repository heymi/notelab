-- NoteLab schema (Supabase Postgres)
-- Apply in Supabase SQL Editor (public schema).

-- =====================================================================
-- 1. Storage Bucket for Attachments
-- =====================================================================
-- Run this first in SQL Editor, or manually create the bucket in Storage settings.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'attachments',
  'attachments',
  false,  -- private bucket, requires auth
  52428800,  -- 50MB max file size
  array['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/heic', 'application/pdf']
)
on conflict (id) do nothing;

-- Storage RLS policies
alter table storage.objects enable row level security;

drop policy if exists "Users can upload own attachments" on storage.objects;
create policy "Users can upload own attachments"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'attachments' and
  (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Users can read own attachments" on storage.objects;
create policy "Users can read own attachments"
on storage.objects for select
to authenticated
using (
  bucket_id = 'attachments' and
  (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Users can delete own attachments" on storage.objects;
create policy "Users can delete own attachments"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'attachments' and
  (storage.foldername(name))[1] = auth.uid()::text
);

-- =====================================================================
-- 2. Attachments Metadata Table
-- =====================================================================
create table if not exists public.attachments (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  note_id uuid not null references public.notes(id) on delete cascade,
  storage_path text not null,  -- e.g. "{user_id}/{attachment_id}.jpg"
  file_name text not null,
  mime_type text not null,
  file_size bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists attachments_user_id_idx on public.attachments(user_id);
create index if not exists attachments_note_id_idx on public.attachments(note_id);
create index if not exists attachments_user_updated_idx on public.attachments(user_id, updated_at);

-- attachments RLS
alter table public.attachments enable row level security;

create policy attachments_select on public.attachments
for select using (user_id = auth.uid());

create policy attachments_insert on public.attachments
for insert with check (user_id = auth.uid());

create policy attachments_update on public.attachments
for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy attachments_delete on public.attachments
for delete using (user_id = auth.uid());

-- updated_at trigger for attachments
drop trigger if exists set_updated_at_attachments on public.attachments;
create trigger set_updated_at_attachments
before update on public.attachments
for each row
execute function public.set_updated_at();

-- =====================================================================
-- 3. Notebooks & Notes Tables
-- =====================================================================

-- Tables
create table if not exists public.notebooks (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  color text not null,
  icon_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists notebooks_user_id_idx on public.notebooks(user_id);
create index if not exists notebooks_user_updated_idx on public.notebooks(user_id, updated_at);

create table if not exists public.notes (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  notebook_id uuid not null references public.notebooks(id) on delete cascade,
  title text not null,
  summary text not null default '',
  content text not null default '',
  content_rtf bytea,
  paragraph_count int not null default 0,
  bullet_count int not null default 0,
  has_additional_context boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version int not null default 1,
  deleted_at timestamptz
);

create index if not exists notes_user_id_idx on public.notes(user_id);
create index if not exists notes_notebook_id_idx on public.notes(notebook_id);
create index if not exists notes_user_updated_idx on public.notes(user_id, updated_at);

-- updated_at triggers
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_updated_at_notebooks on public.notebooks;
create trigger set_updated_at_notebooks
before update on public.notebooks
for each row
execute function public.set_updated_at();

drop trigger if exists set_updated_at_notes on public.notes;
create trigger set_updated_at_notes
before update on public.notes
for each row
execute function public.set_updated_at();

-- version bump trigger (optimistic locking support)
create or replace function public.bump_version()
returns trigger
language plpgsql
as $$
begin
  new.version = old.version + 1;
  return new;
end;
$$;

drop trigger if exists bump_version_notes on public.notes;
create trigger bump_version_notes
before update on public.notes
for each row
execute function public.bump_version();

-- RLS
alter table public.notebooks enable row level security;
alter table public.notes enable row level security;

drop policy if exists notebooks_select on public.notebooks;
create policy notebooks_select
on public.notebooks
for select
using (user_id = auth.uid());

drop policy if exists notebooks_insert on public.notebooks;
create policy notebooks_insert
on public.notebooks
for insert
with check (user_id = auth.uid());

drop policy if exists notebooks_update on public.notebooks;
create policy notebooks_update
on public.notebooks
for update
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists notebooks_delete on public.notebooks;
create policy notebooks_delete
on public.notebooks
for delete
using (user_id = auth.uid());

drop policy if exists notes_select on public.notes;
create policy notes_select
on public.notes
for select
using (user_id = auth.uid());

drop policy if exists notes_insert on public.notes;
create policy notes_insert
on public.notes
for insert
with check (user_id = auth.uid());

drop policy if exists notes_update on public.notes;
create policy notes_update
on public.notes
for update
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists notes_delete on public.notes;
create policy notes_delete
on public.notes
for delete
using (user_id = auth.uid());

