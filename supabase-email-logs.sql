-- ZIVRA transactional email send log
create table if not exists public.zivra_email_logs (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  email_type text not null check (email_type in ('received','confirmed','processing','shipped','out_for_delivery','delivered')),
  recipient text not null,
  sent_by text not null check (sent_by in ('checkout','admin')),
  sent_at timestamptz not null default now()
);
create index if not exists zivra_email_logs_order_idx on public.zivra_email_logs(order_id, sent_at desc);
alter table public.zivra_email_logs enable row level security;
revoke all on public.zivra_email_logs from anon, authenticated;
