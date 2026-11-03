-- ZIVRA Help Centre messages
-- Run once in Supabase Dashboard -> SQL Editor.
-- Public visitors can submit only through the validated RPC below.
-- Only authenticated ZIVRA admins can read/update/delete inbox records.

create table if not exists public.zivra_messages (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email text not null,
  phone text not null default '',
  subject text not null default 'Help Centre message',
  message text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists zivra_messages_created_idx
  on public.zivra_messages(created_at desc);

alter table public.zivra_messages enable row level security;
revoke all on public.zivra_messages from anon, authenticated;
grant select, update, delete on public.zivra_messages to authenticated;

drop policy if exists "Admins read customer messages" on public.zivra_messages;
create policy "Admins read customer messages"
  on public.zivra_messages for select to authenticated
  using (public.zivra_is_admin());

drop policy if exists "Admins update customer messages" on public.zivra_messages;
create policy "Admins update customer messages"
  on public.zivra_messages for update to authenticated
  using (public.zivra_is_admin())
  with check (public.zivra_is_admin());

drop policy if exists "Admins delete customer messages" on public.zivra_messages;
create policy "Admins delete customer messages"
  on public.zivra_messages for delete to authenticated
  using (public.zivra_is_admin());

create or replace function public.zivra_submit_message(
  p_name text,
  p_email text,
  p_message text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name text := trim(coalesce(p_name, ''));
  v_email text := lower(trim(coalesce(p_email, '')));
  v_message text := trim(coalesce(p_message, ''));
begin
  if length(v_name) < 1 or length(v_name) > 120 then
    raise exception 'Please enter a valid name.';
  end if;
  if length(v_email) < 5 or length(v_email) > 254
     or v_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' then
    raise exception 'Please enter a valid email address.';
  end if;
  if length(v_message) < 1 or length(v_message) > 5000 then
    raise exception 'Message must be between 1 and 5000 characters.';
  end if;
  if (select count(*) from public.zivra_messages
      where lower(email) = v_email and created_at > now() - interval '15 minutes') >= 5 then
    raise exception 'Too many messages. Please try again later.';
  end if;
  insert into public.zivra_messages(name,email,phone,subject,message)
  values (v_name,v_email,'','Help Centre message',v_message);
end;
$$;

revoke all on function public.zivra_submit_message(text,text,text) from public;
grant execute on function public.zivra_submit_message(text,text,text) to anon, authenticated;
