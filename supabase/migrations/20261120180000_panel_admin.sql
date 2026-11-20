-- Panel de administración: anulación de cierres, vista de análisis y permisos
--
-- Definiciones acordadas con el negocio:
--   * "Total S/" del formulario (total_manual) es el EFECTIVO en caja.
--   * Venta del día = efectivo + Yape/Plin.
--   * "N° operación" (n_op) es la CANTIDAD de pagos por el POS del agente bancario.
--   * La impresión B/N no se calcula; no hay cuadre por ahora.
--   * Un cierre sin efectivo ni Yape se guarda, pero no entra en las estadísticas.
--   * Duplicados y pruebas se anulan con motivo (reversible y auditado).

-- 1) Anulación ------------------------------------------------------------------

alter table public.caja_cierres
  add column if not exists anulado        boolean not null default false,
  add column if not exists anulado_motivo text,
  add column if not exists anulado_por    uuid,
  add column if not exists anulado_en     timestamptz;

comment on column public.caja_cierres.total_manual is 'Efectivo en caja (campo "Total S/" del formulario).';
comment on column public.caja_cierres.n_op is 'Cantidad de pagos por el POS del agente bancario (texto tal como se ingresó).';
comment on column public.caja_cierres.anulado is 'true = excluido de las estadísticas por un administrador (ver anulado_motivo y auditoria).';

create or replace function public.caja_cierre_anular(p_id bigint, p_motivo text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_fecha date;
begin
  if not public.es_admin() then
    raise exception 'Solo un administrador puede anular cierres' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_motivo, ''))) < 3 then
    raise exception 'Indica el motivo de la anulación' using errcode = '22023';
  end if;

  update public.caja_cierres
     set anulado = true, anulado_motivo = left(btrim(p_motivo), 200),
         anulado_por = (select auth.uid()), anulado_en = now()
   where id = p_id and not anulado
  returning fecha into v_fecha;
  if not found then
    raise exception 'El cierre no existe o ya está anulado' using errcode = 'P0002';
  end if;

  insert into public.auditoria (actor_id, actor_email, accion, entidad, entidad_id, detalle)
  values ((select auth.uid()), (select auth.jwt() ->> 'email'), 'cierre.anular', 'caja_cierre',
          p_id::text, jsonb_build_object('fecha', v_fecha, 'motivo', btrim(p_motivo)));
end
$$;

create or replace function public.caja_cierre_restaurar(p_id bigint)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_fecha  date;
  v_motivo text;
begin
  if not public.es_admin() then
    raise exception 'Solo un administrador puede restaurar cierres' using errcode = '42501';
  end if;

  select fecha, anulado_motivo into v_fecha, v_motivo
    from public.caja_cierres where id = p_id and anulado;
  if not found then
    raise exception 'El cierre no existe o no está anulado' using errcode = 'P0002';
  end if;

  update public.caja_cierres
     set anulado = false, anulado_motivo = null, anulado_por = null, anulado_en = null
   where id = p_id;

  insert into public.auditoria (actor_id, actor_email, accion, entidad, entidad_id, detalle)
  values ((select auth.uid()), (select auth.jwt() ->> 'email'), 'cierre.restaurar', 'caja_cierre',
          p_id::text, jsonb_build_object('fecha', v_fecha, 'motivo_anterior', v_motivo));
end
$$;

revoke execute on function public.caja_cierre_anular(bigint, text) from public, anon;
revoke execute on function public.caja_cierre_restaurar(bigint) from public, anon;
grant  execute on function public.caja_cierre_anular(bigint, text) to authenticated;
grant  execute on function public.caja_cierre_restaurar(bigint) to authenticated;

-- 2) El historial con montos solo lo leen administradores -----------------------
-- La caja no lee caja_cierres (cierra con caja_cerrar, SECURITY DEFINER).

drop policy if exists cierres_sel on public.caja_cierres;
create policy cierres_sel on public.caja_cierres for select to authenticated
  using ((select public.es_admin()));

-- 3) Vista del panel --------------------------------------------------------------
-- security_invoker: respeta el RLS de caja_cierres (solo admin ve filas).
-- Los montos se calculan en numeric (exactos); la pantalla solo los formatea.

create or replace view public.cierres_panel
with (security_invoker = on) as
select c.id,
       c.fecha,
       c.turno,
       nullif(btrim(c.operador), '')                         as operador,
       c.libreria_total                                       as libreria,
       c.color, c.a3, c.scan, c.espiral,
       c.yape_plin                                            as yape,
       c.total_manual                                         as efectivo,
       c.n_op,
       case when btrim(c.n_op) ~ '^\d{1,6}$' then btrim(c.n_op)::int end as ops_agente,
       coalesce(c.total_manual, 0) + coalesce(c.yape_plin, 0) as venta,
       (c.total_manual is not null or c.yape_plin is not null) as completo,
       c.anulado, c.anulado_motivo, c.anulado_en,
       -- Mismo día, mismo efectivo y mismo Yape que otro cierre vigente
       (c.total_manual is not null or c.yape_plin is not null)
         and exists (select 1 from public.caja_cierres d
                      where d.fecha = c.fecha and d.id <> c.id and not d.anulado
                        and d.total_manual is not distinct from c.total_manual
                        and d.yape_plin   is not distinct from c.yape_plin) as posible_duplicado,
       c.items,
       c.created_at
  from public.caja_cierres c;

comment on view public.cierres_panel is
  'Cierres con los cálculos del panel de administración (venta = efectivo + Yape). Solo administradores ven filas.';

revoke all on public.cierres_panel from anon;
grant select on public.cierres_panel to authenticated;
