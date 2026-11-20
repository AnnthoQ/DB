-- ping(): la llama cada pocos minutos el workflow .github/workflows/mantener-despierto.yml
--
-- El proyecto corre en la instancia Nano (0,5 GB). Tras horas sin uso, su memoria
-- pasa a disco y el primer login tardaba 10-18 s (o fallaba por timeout). Esta
-- función lee las mismas tablas e índices que usa el login y la caja para que
-- sigan en memoria. No devuelve datos: solo true.
--
-- SECURITY DEFINER porque anon no puede leer esas tablas; no recibe parámetros
-- ni expone filas, así que llamarla sin sesión no filtra información.

create or replace function public.ping()
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $$
begin
  perform count(*) from auth.users;
  perform count(*) from auth.refresh_tokens where not revoked;
  perform count(*) from public.profiles where activo;
  perform count(*) from public.productos;
  perform count(*) from public.caja_items where cierre_id is null;
  return true;
end
$$;

revoke execute on function public.ping() from public;
grant  execute on function public.ping() to anon, authenticated;
