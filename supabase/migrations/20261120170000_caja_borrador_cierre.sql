-- Borrador compartido del cierre de caja
--
-- Los campos de "Cerrar caja" (turno, operador, montos, N° de operación, total)
-- se guardan en una sola fila y se sincronizan en tiempo real entre
-- dispositivos. Cada campo se escribe por separado con caja_borrador_set(), así
-- dos personas editando campos distintos no se pisan; en el mismo campo gana el
-- último. caja_cerrar() vacía el borrador en la misma transacción del cierre.

create table if not exists public.caja_borrador (
  id              smallint primary key default 1 check (id = 1),
  datos           jsonb not null default '{}'::jsonb,
  origen          text,          -- dispositivo que hizo el último cambio (para ignorar su propio eco)
  actualizado_por uuid default auth.uid(),
  actualizado_en  timestamptz not null default now()
);

comment on table public.caja_borrador is
  'Borrador del cierre de caja en curso (una sola fila). Se escribe solo con caja_borrador_set() y se vacía en caja_cerrar().';

insert into public.caja_borrador (id) values (1) on conflict (id) do nothing;

alter table public.caja_borrador enable row level security;

drop policy if exists borrador_sel on public.caja_borrador;
create policy borrador_sel on public.caja_borrador for select to authenticated
  using ((select public.es_operador()));
-- Sin políticas de escritura: solo se modifica con las funciones de abajo.

-- Guarda (o borra, si el valor viene vacío) un campo del borrador -------------

create or replace function public.caja_borrador_set(p_campo text, p_valor text, p_origen text default null)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if not public.es_operador() then
    raise exception 'Tu cuenta no tiene acceso a la caja' using errcode = '42501';
  end if;
  if p_campo not in ('turno', 'operador', 'color', 'a3', 'scan', 'espiral', 'yape_plin', 'n_op', 'total_manual') then
    raise exception 'Campo no válido: %', p_campo using errcode = '22023';
  end if;
  if length(p_valor) > 60 then
    raise exception 'Valor demasiado largo' using errcode = '22001';
  end if;

  -- Un solo UPDATE por campo: la fila se bloquea y los cambios simultáneos a
  -- campos distintos se aplican uno tras otro sin perderse.
  update public.caja_borrador
     set datos = case when coalesce(p_valor, '') = '' then datos - p_campo
                      else datos || jsonb_build_object(p_campo, p_valor) end,
         origen = left(p_origen, 64),
         actualizado_por = (select auth.uid()),
         actualizado_en = now()
   where id = 1;
end
$$;

revoke execute on function public.caja_borrador_set(text, text, text) from public, anon;
grant  execute on function public.caja_borrador_set(text, text, text) to authenticated;

-- Tiempo real ----------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'caja_borrador') then
    alter publication supabase_realtime add table public.caja_borrador;
  end if;
end
$$;

-- caja_cerrar: igual que antes, y además vacía el borrador ---------------------

create or replace function public.caja_cerrar(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_id    bigint;
  v_items jsonb;
  v_tot   numeric;
begin
  if not public.es_operador() then
    raise exception 'Tu cuenta no tiene acceso a la caja' using errcode = '42501';
  end if;

  insert into public.caja_cierres
    (turno, operador, color, a3, scan, espiral, impresion, yape_plin, n_op,
     total_manual, libreria_total, items)
  values
    (p->>'turno', p->>'operador', (p->>'color')::numeric, (p->>'a3')::numeric,
     (p->>'scan')::numeric, (p->>'espiral')::numeric, (p->>'impresion')::numeric,
     (p->>'yape_plin')::numeric, p->>'n_op', (p->>'total_manual')::numeric,
     0, '[]'::jsonb)
  returning id into v_id;

  -- Las líneas que este UPDATE marca son exactamente las que se suman.
  with cerradas as (
    update public.caja_items
       set cierre_id = v_id
     where cierre_id is null
    returning id, producto_id, nombre, cantidad, precio_unitario
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'producto_id', producto_id,
           'nombre',      nombre,
           'cantidad',    cantidad,
           'subtotal',    cantidad * precio_unitario) order by id), '[]'::jsonb),
         coalesce(sum(cantidad * precio_unitario), 0)
    into v_items, v_tot
    from cerradas;

  -- El error deshace también el INSERT del cierre.
  if jsonb_array_length(v_items) = 0 then
    raise exception 'No hay ventas registradas';
  end if;

  update public.caja_cierres
     set libreria_total = v_tot, items = v_items
   where id = v_id;

  -- El siguiente turno empieza con el borrador vacío en todos los dispositivos.
  update public.caja_borrador
     set datos = '{}'::jsonb, origen = null,
         actualizado_por = (select auth.uid()), actualizado_en = now()
   where id = 1;

  return jsonb_build_object('id', v_id, 'items', v_items);
end
$$;

revoke execute on function public.caja_cerrar(jsonb) from public, anon;
grant  execute on function public.caja_cerrar(jsonb) to authenticated;
