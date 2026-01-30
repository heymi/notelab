# AI Jobs Tables (Supabase SQL)

```sql
create extension if not exists pgcrypto;

create table if not exists public.ai_jobs (
  id uuid primary key default gen_random_uuid(),
  device_id text,
  job_type text not null check (job_type in ('plan')),
  status text not null check (status in ('queued','running','done','failed')),
  stage text,
  progress int,
  result_json jsonb,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists ai_jobs_device_id_idx on public.ai_jobs (device_id);
create index if not exists ai_jobs_created_at_idx on public.ai_jobs (created_at desc);

create table if not exists public.ai_job_events (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.ai_jobs(id) on delete cascade,
  ts timestamptz not null default now(),
  stage text not null,
  message text not null,
  payload_json jsonb
);

create index if not exists ai_job_events_job_id_idx on public.ai_job_events (job_id, ts desc);
```
