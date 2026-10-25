# Validación realizada

Probado en Docker Desktop con contenedores Linux:

- `docker compose config --quiet`: configuración válida.
- `docker compose up -d --wait`: inicialización completa y servicio saludable.
- Servidor real: PostgreSQL 17.11, imagen fijada por digest en `compose.yaml`.
- `tests/integridad.sql`: pasó en la base real y después de restaurar el respaldo; sus datos se revierten.
- `scripts/backup.ps1`: produjo un respaldo custom de PostgreSQL.
- `scripts/restore.ps1`: restauró ese respaldo sobre esta base recién creada.
- Reinicio y recreación del contenedor: conservó el esquema y las seis categorías en el volumen.

No se insertan usuarios ni actividades de demostración permanentes. No se probaron envíos de correo, notificaciones, integración con APIs ni conexiones desde otra computadora. No se realizaron pruebas de carga o concurrencia.
