-- Caja: cierre atómico y protección del historial
--
-- 1) caja_cerrar marcaba las líneas abiertas DESPUÉS de leerlas. Una venta
--    registrada entre ambos pasos quedaba dentro del cierre sin sumarse al total
--    ni salir en el PDF. Ahora un solo UPDATE ... RETURNING decide qué líneas
--    entran, y el total y el detalle se calculan exactamente con esas líneas.
--    El detalle incluye producto_id para ordenar el PDF por página del Kardex.
--
-- 2) items_all dejaba a cualquier operador editar o borrar líneas de cierres ya
--    hechos, y cierres_ins le dejaba insertar un cierre con cualquier total.
--    Ahora los operadores solo tocan líneas abiertas (cierre_id is null), solo
--    un administrador corrige líneas cerradas, y los cierres se crean únicamente
--    con caja_cerrar (SECURITY DEFINER, verifica es_operador()).

-- 1) Cierre atómico ------------------------------------------------------------

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

  return jsonb_build_object('id', v_id, 'items', v_items);
end
$$;

revoke execute on function public.caja_cerrar(jsonb) from public, anon;
grant  execute on function public.caja_cerrar(jsonb) to authenticated;

-- 2) Historial protegido -------------------------------------------------------

drop policy if exists items_all on public.caja_items;

create policy items_sel on public.caja_items for select to authenticated
  using ((select public.es_operador()));

create policy items_ins on public.caja_items for insert to authenticated
  with check ((select public.es_operador()) and cierre_id is null);

create policy items_upd on public.caja_items for update to authenticated
  using (((select public.es_operador()) and cierre_id is null) or (select public.es_admin()))
  with check (((select public.es_operador()) and cierre_id is null) or (select public.es_admin()));

create policy items_del on public.caja_items for delete to authenticated
  using (((select public.es_operador()) and cierre_id is null) or (select public.es_admin()));

-- Los cierres solo nacen de caja_cerrar().
drop policy if exists cierres_ins on public.caja_cierres;
