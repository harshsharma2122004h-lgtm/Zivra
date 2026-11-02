-- ZIVRA private system error log
-- Run once in Supabase SQL Editor. Customer-facing pages submit diagnostics through a
-- SECURITY DEFINER RPC; only authenticated ZIVRA admins can read the log.

create table if not exists public.zivra_error_logs (
  id bigint generated always as identity primary key,
  source text not null,
  error_code text not null default 'UNCLASSIFIED',
  error_message text not null,
  page_path text not null default '/',
  created_at timestamptz not null default now()
);

create index if not exists zivra_error_logs_created_idx
  on public.zivra_error_logs(created_at desc);

alter table public.zivra_error_logs enable row level security;
revoke all on public.zivra_error_logs from anon, authenticated;
grant select on public.zivra_error_logs to authenticated;

drop policy if exists "Admins read system error logs" on public.zivra_error_logs;
create policy "Admins read system error logs"
  on public.zivra_error_logs for select to authenticated
  using (public.zivra_is_admin());

create or replace function public.zivra_log_client_error(
  p_source text,
  p_code text,
  p_message text,
  p_page text default '/'
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_message text;
begin
  v_message := left(coalesce(p_message, 'Unknown client error'), 1000);
  -- Strip email addresses and phone-like sequences before storing diagnostics.
  v_message := regexp_replace(v_message, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[email]', 'gi');
  v_message := regexp_replace(v_message, '(\+?[0-9][0-9 ()-]{7,}[0-9])', '[phone]', 'g');
  if (select count(*) from public.zivra_error_logs
      where created_at > now() - interval '5 minutes') < 200 then
    insert into public.zivra_error_logs(source,error_code,error_message,page_path)
    values (
      left(coalesce(nullif(p_source,''),'storefront'),80),
      left(coalesce(nullif(p_code,''),'UNCLASSIFIED'),80),
      v_message,
      left(coalesce(nullif(p_page,''),'/'),200)
    );
  end if;
end;
$$;

revoke all on function public.zivra_log_client_error(text,text,text,text) from public;
grant execute on function public.zivra_log_client_error(text,text,text,text) to anon, authenticated;
