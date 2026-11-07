-- ZIVRA private system error log (admin Notifications inbox)
-- Run this after supabase-schema.sql. Safe to re-run.
-- Supports the storefront RPC payload and the admin.html inbox fields.

create table if not exists public.zivra_error_logs (
  id bigint generated always as identity primary key,
  source text not null,
  error_code text not null default 'UNCLASSIFIED',
  error_message text not null default '',
  page_path text not null default '/',
  message text not null default '',
  page text not null default '/',
  user_agent text,
  details jsonb not null default '{}'::jsonb,
  occurrences integer not null default 1,
  is_read boolean not null default false,
  created_at timestamptz not null default now(),
  last_seen timestamptz not null default now()
);

-- Bring forward installations that ran the earlier, smaller version.
alter table public.zivra_error_logs add column if not exists message text not null default '';
alter table public.zivra_error_logs add column if not exists page text not null default '/';
alter table public.zivra_error_logs add column if not exists user_agent text;
alter table public.zivra_error_logs add column if not exists details jsonb not null default '{}'::jsonb;
alter table public.zivra_error_logs add column if not exists occurrences integer not null default 1;
alter table public.zivra_error_logs add column if not exists is_read boolean not null default false;
alter table public.zivra_error_logs add column if not exists last_seen timestamptz not null default now();

update public.zivra_error_logs
set message = coalesce(nullif(message,''), error_message),
    page = coalesce(nullif(page,'/'), page_path),
    last_seen = coalesce(last_seen, created_at)
where message = '' or page = '/';

create index if not exists zivra_error_logs_last_seen_idx
  on public.zivra_error_logs(last_seen desc);

alter table public.zivra_error_logs enable row level security;
revoke all on public.zivra_error_logs from anon, authenticated;
grant select, update, delete on public.zivra_error_logs to authenticated;

drop policy if exists "Admins read system error logs" on public.zivra_error_logs;
create policy "Admins read system error logs"
  on public.zivra_error_logs for select to authenticated
  using (public.zivra_is_admin());

drop policy if exists "Admins update system error logs" on public.zivra_error_logs;
create policy "Admins update system error logs"
  on public.zivra_error_logs for update to authenticated
  using (public.zivra_is_admin())
  with check (public.zivra_is_admin());

drop policy if exists "Admins delete system error logs" on public.zivra_error_logs;
create policy "Admins delete system error logs"
  on public.zivra_error_logs for delete to authenticated
  using (public.zivra_is_admin());

create or replace function public.zivra_log_client_error(
  p_source text,
  p_message text,
  p_page text default '/',
  p_details jsonb default '{}'::jsonb,
  p_user_agent text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_message text;
  v_page text := left(coalesce(nullif(p_page,''),'/'),200);
  v_details jsonb := coalesce(p_details,'{}'::jsonb);
  v_user_agent text := left(coalesce(p_user_agent,''),500);
begin
  v_message := left(coalesce(p_message,'Unknown client error'),1000);
  -- Redact common contact details from stored diagnostics.
  v_message := regexp_replace(v_message,'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}','[email]','gi');
  v_message := regexp_replace(v_message,'(\+?[0-9][0-9 ()-]{7,}[0-9])','[phone]','g');

  if (select count(*) from public.zivra_error_logs
      where created_at > now() - interval '5 minutes') < 200 then
    insert into public.zivra_error_logs(
      source,error_code,error_message,page_path,
      message,page,user_agent,details,occurrences,is_read,created_at,last_seen
    ) values (
      left(coalesce(nullif(p_source,''),'storefront'),80),
      'UNCLASSIFIED',v_message,v_page,
      v_message,v_page,v_user_agent,v_details,1,false,now(),now()
    );
  end if;
end;
$$;

revoke all on function public.zivra_log_client_error(text,text,text,jsonb,text) from public;
grant execute on function public.zivra_log_client_error(text,text,text,jsonb,text) to anon, authenticated;
