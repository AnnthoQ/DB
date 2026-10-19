<h1 align="center">Caja SENATI · Punto de venta PWA</h1>

<p align="center">
Aplicación web instalable para registrar las ventas de una librería/fotocopiadora y <b>cerrar caja con reporte PDF</b>.<br>
Funciona sin conexión, sincroniza el catálogo en tiempo real y controla el acceso por operador con <b>Supabase Auth</b>.
</p>

<p align="center"><a href="https://annthoq.github.io/DB/"><b>Abrir la app</b></a></p>

---

## El problema que resuelve

El cierre de caja se llevaba en papel o en hojas de cálculo: los precios cambiaban, las sumas se hacían a mano y el reporte del turno tomaba tiempo. Esta PWA permite al operador **buscar un producto, registrarlo en segundos y generar el PDF de cierre** con totales por medio de pago, desde el celular y aunque se caiga el Wi-Fi.

## Demo

<!-- Sustituye por capturas reales: docs/login.png, docs/caja.png, docs/pdf.png -->
<p align="center">
  <img src="docs/caja.png" width="260" alt="Registro de ventas">
  <img src="docs/pdf.png"  width="260" alt="Reporte PDF de cierre">
</p>

## Tech Stack

| Capa | Tecnología |
|---|---|
| Frontend | HTML5, CSS3, JavaScript sin frameworks (mobile-first) |
| Backend | [Supabase](https://supabase.com): Postgres, Auth, Realtime y funciones RPC |
| Offline | Service Worker (red primero para páginas, caché primero para estáticos) + IndexedDB |
| Reportes | [jsPDF](https://github.com/parallax/jsPDF) 2.5.1 |
| Instalación | Web App Manifest con íconos *maskable* |
| Hosting | GitHub Pages |

## Características

- **Inicio de sesión por operador** (código + contraseña) y verificación de permisos con la RPC `es_operador`.
- **Búsqueda tolerante** de productos con puntuación por relevancia (p. ej. "impresión", "espiral", "A3").
- **Catálogo en caché** (IndexedDB): la app abre al instante y sigue funcionando sin red.
- **Sincronización en tiempo real** de los ítems de caja entre dispositivos (`postgres_changes` sobre `caja_items`).
- **Alta rápida de productos** con nombre, precio y código.
- **Cierre de caja** (RPC `caja_cerrar`) con turno, operador, desglose por servicio y Yape/Plin con N° de operación.
- **PDF configurable:** papel, escala y márgenes, con vista previa antes de generarlo.
- **Ajustes de tema** claro/oscuro, vibración háptica e instalable como app nativa.

## Instalación y ejecución local

```bash
git clone https://github.com/AnnthoQ/DB.git
cd DB
python -m http.server 8080      # el Service Worker requiere http://, no file://
```

Abre `http://localhost:8080`.

### Backend propio (opcional)

1. Crea un proyecto en Supabase y usuarios en **Authentication** con correo `<código>@inv.local`.
2. Crea las tablas `productos` y `caja_items`, activa RLS y Realtime sobre `caja_items`.
3. Crea las funciones `es_operador()`, `caja_ajustar(...)` y `caja_cerrar(...)`.
4. Cambia las constantes `SB` y `KEY` en `index.html`.

> Al publicar una nueva versión, sube el número de `CACHE` en `sw.js` para forzar la actualización en los dispositivos.

## Arquitectura

```
DB/
├── index.html             # Interfaz, estilos y lógica (auth, búsqueda, caja, PDF)
├── sw.js                  # Service Worker: caché del shell y librerías CDN
├── manifest.webmanifest   # Metadatos de instalación PWA
├── icon-192.png           # Íconos de la app
├── icon-512.png
├── icon-maskable-512.png
└── apple-touch-icon.png
```

```
 Operador ─▶ Supabase Auth ─▶ es_operador()
    │
    ├── catálogo ◀── productos (IndexedDB como caché)
    ├── ventas  ◀──▶ caja_items (Realtime)
    └── cierre  ──▶ caja_cerrar() ──▶ jsPDF
```

## Licencia y contacto

Distribuido bajo licencia [MIT](LICENSE). Hecho por [@AnnthoQ](https://github.com/AnnthoQ).
