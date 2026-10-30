-- ZIVRA customer order tracking (safe public lookup by order number + checkout email)
create or replace function public.zivra_track_order(p_order_number text, p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order public.orders%rowtype;
begin
  select * into v_order
  from public.orders
  where upper(order_number) = upper(trim(p_order_number))
    and lower(email) = lower(trim(p_email))
  limit 1;

  if not found then
    return jsonb_build_object('error','not_found');
  end if;

  return jsonb_build_object(
    'order_number', v_order.order_number,
    'status', v_order.status,
    'payment_method', v_order.payment_method,
    'payment_status', v_order.payment_status,
    'total', v_order.total,
    'created_at', v_order.created_at
  );
end;
$$;

revoke all on function public.zivra_track_order(text,text) from public;
grant execute on function public.zivra_track_order(text,text) to anon, authenticated;
