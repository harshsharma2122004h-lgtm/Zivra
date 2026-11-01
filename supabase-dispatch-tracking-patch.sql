-- ZIVRA dispatch and customer tracking upgrade. Run once in Supabase SQL Editor.
alter table public.orders add column if not exists courier_name text;
alter table public.orders add column if not exists tracking_number text;
alter table public.orders add column if not exists tracking_url text;
alter table public.orders add column if not exists shipped_at timestamptz;
alter table public.orders add column if not exists delivered_at timestamptz;

create or replace function public.zivra_track_order(p_order_number text, p_email text)
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
 select jsonb_build_object(
  'order_number',o.order_number,'status',o.status,'payment_method',o.payment_method,
  'payment_status',o.payment_status,'subtotal',o.subtotal,'shipping',o.shipping,'total',o.total,
  'created_at',o.created_at,'customer_name',o.customer_name,'address',o.address,
  'city',o.city,'pincode',o.pincode,'courier_name',o.courier_name,
  'tracking_number',o.tracking_number,'tracking_url',o.tracking_url,
  'shipped_at',o.shipped_at,'delivered_at',o.delivered_at,
  'items',coalesce((select jsonb_agg(jsonb_build_object('product_name',oi.product_name,'sku',oi.sku,'quantity',oi.quantity,'size',oi.size,'color',oi.color,'unit_price',oi.unit_price,'line_total',oi.line_total) order by oi.product_name) from public.order_items oi where oi.order_id=o.id),'[]'::jsonb)
 ) from public.orders o
 where upper(o.order_number)=upper(trim(p_order_number)) and lower(o.email)=lower(trim(p_email)) limit 1;
$$;
revoke all on function public.zivra_track_order(text,text) from public;
grant execute on function public.zivra_track_order(text,text) to anon, authenticated;
