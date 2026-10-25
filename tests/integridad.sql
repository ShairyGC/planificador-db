\set ON_ERROR_STOP on
BEGIN;
-- Todas las filas se revierten al terminar. Las secuencias pueden avanzar.
DO $$
DECLARE u bigint; otro bigint; l bigint; l2 bigint; a bigint; a2 bigint;
        c bigint; r bigint; fecha timestamptz;
BEGIN
    INSERT INTO usuarios (nombres, apellidos, correo_electronico, nombre_usuario, password_hash)
    VALUES ('Prueba', 'Uno', 'prueba-' || txid_current() || '@example.invalid',
            'prueba-' || txid_current(), '$2b$12$hash_ficticio_solo_prueba') RETURNING id_usuario INTO u;
    INSERT INTO usuarios (nombres, apellidos, correo_electronico, nombre_usuario, password_hash)
    VALUES ('Prueba', 'Dos', 'otro-' || txid_current() || '@example.invalid',
            'otro-' || txid_current(), '$2b$12$hash_ficticio_solo_prueba') RETURNING id_usuario INTO otro;
    BEGIN
        UPDATE usuarios SET nombre_usuario = 'modificado' WHERE id_usuario = u;
        RAISE EXCEPTION 'FALLO: username editable';
    EXCEPTION WHEN check_violation THEN NULL; END;
    BEGIN
        INSERT INTO usuarios (nombres, apellidos, correo_electronico, nombre_usuario, password_hash)
        SELECT nombres, apellidos, correo_electronico, 'duplicado', password_hash
        FROM usuarios WHERE id_usuario = u;
        RAISE EXCEPTION 'FALLO: correo duplicado';
    EXCEPTION WHEN unique_violation THEN NULL; END;
    SELECT fecha_actualizacion INTO fecha FROM usuarios WHERE id_usuario = u;
    UPDATE usuarios SET telefono = '55555555' WHERE id_usuario = u;
    IF (SELECT fecha_actualizacion <= fecha FROM usuarios WHERE id_usuario = u) THEN
        RAISE EXCEPTION 'FALLO: timestamp'; END IF;

    INSERT INTO ubicacion (id_usuario, nombre_lugar, direccion_formateada, latitud, longitud, origen_ubicacion)
    VALUES (u, 'Lugar', 'Guatemala', 14.6, -90.5, 'GPS_MANUAL') RETURNING id_ubicacion INTO l;
    INSERT INTO ubicacion (id_usuario, nombre_lugar, direccion_formateada, latitud, longitud, origen_ubicacion)
    VALUES (u, 'Segundo', 'Guatemala', 14.6, -90.5, 'GPS_MANUAL') RETURNING id_ubicacion INTO l2;
    BEGIN
        UPDATE ubicacion SET latitud = 100 WHERE id_ubicacion = l;
        RAISE EXCEPTION 'FALLO: coordenadas';
    EXCEPTION WHEN check_violation THEN NULL; END;
    INSERT INTO categoria_pasatiempos (nombre_categoria)
    VALUES ('Prueba-' || txid_current()) RETURNING id_categoria INTO c;
    INSERT INTO actividad (id_usuario, id_ubicacion, id_categoria, titulo_actividad,
                           fecha_hora_inicio, fecha_hora_fin, tipo_entorno)
    VALUES (u, l, c, 'Primera', '2099-01-01 08:00-06', '2099-01-01 09:00-06', 'OUTDOOR')
    RETURNING id_actividad INTO a;
    BEGIN
        INSERT INTO actividad (id_usuario, id_ubicacion, titulo_actividad,
                               fecha_hora_inicio, fecha_hora_fin, tipo_entorno)
        VALUES (u, l, 'Traslape', '2099-01-01 08:30-06', '2099-01-01 09:30-06', 'OUTDOOR');
        RAISE EXCEPTION 'FALLO: traslape permitido';
    EXCEPTION WHEN exclusion_violation THEN NULL; END;
    BEGIN
        INSERT INTO actividad (id_usuario, id_ubicacion, titulo_actividad,
                               fecha_hora_inicio, fecha_hora_fin, tipo_entorno)
        VALUES (otro, l, 'Ajena', '2099-01-01 08:00-06', '2099-01-01 09:00-06', 'OUTDOOR');
        RAISE EXCEPTION 'FALLO: ubicacion ajena';
    EXCEPTION WHEN foreign_key_violation THEN NULL; END;
    BEGIN
        UPDATE actividad SET fecha_hora_fin = fecha_hora_inicio WHERE id_actividad = a;
        RAISE EXCEPTION 'FALLO: duracion cero';
    EXCEPTION WHEN check_violation THEN NULL; END;
    BEGIN
        UPDATE actividad SET calificacion_nps = 6 WHERE id_actividad = a;
        RAISE EXCEPTION 'FALLO: calificacion 6';
    EXCEPTION WHEN check_violation THEN NULL; END;

    INSERT INTO actividad (id_usuario, id_ubicacion, titulo_actividad,
                           fecha_hora_inicio, fecha_hora_fin, tipo_entorno, estado_actividad, calificacion_nps)
    VALUES (u, l, 'Consecutiva', '2099-01-01 09:00-06', '2099-01-01 10:00-06', 'INDOOR', 'REALIZADA', 3)
    RETURNING id_actividad INTO a2;
    UPDATE actividad SET estado_actividad = 'REALIZADA', calificacion_nps = 5 WHERE id_actividad = a;
    IF NOT EXISTS (SELECT FROM ubicacion WHERE id_ubicacion = l
                   AND visitas_acumuladas = 2 AND calificacion_promedio = 4) THEN
        RAISE EXCEPTION 'FALLO: promedio/visitas'; END IF;
    UPDATE actividad SET id_ubicacion = l2 WHERE id_actividad = a2;
    IF NOT EXISTS (SELECT FROM ubicacion WHERE id_ubicacion = l
                   AND visitas_acumuladas = 1 AND calificacion_promedio = 5)
       OR NOT EXISTS (SELECT FROM ubicacion WHERE id_ubicacion = l2
                   AND visitas_acumuladas = 1 AND calificacion_promedio = 3) THEN
        RAISE EXCEPTION 'FALLO: mover actividad'; END IF;
    DELETE FROM actividad WHERE id_actividad = a2;
    IF NOT EXISTS (SELECT FROM ubicacion WHERE id_ubicacion = l2
                   AND visitas_acumuladas = 0 AND calificacion_promedio = 0) THEN
        RAISE EXCEPTION 'FALLO: borrar actividad/cache'; END IF;
    INSERT INTO actividad (id_usuario, id_ubicacion, titulo_actividad,
                           fecha_hora_inicio, fecha_hora_fin, tipo_entorno, estado_actividad)
    VALUES (u, l, 'Cancelada', '2099-01-01 08:00-06', '2099-01-01 09:00-06', 'INDOOR', 'CANCELADA');

    DELETE FROM categoria_pasatiempos WHERE id_categoria = c;
    IF NOT EXISTS (SELECT FROM actividad WHERE id_actividad = a AND id_categoria IS NULL) THEN
        RAISE EXCEPTION 'FALLO: categoria SET NULL'; END IF;
    INSERT INTO alarma_recordatorio (id_actividad, minutos_anticipacion) VALUES (a, 15), (a, 30);
    BEGIN
        INSERT INTO alarma_recordatorio (id_actividad, minutos_anticipacion) VALUES (a, -1);
        RAISE EXCEPTION 'FALLO: anticipacion negativa';
    EXCEPTION WHEN check_violation THEN NULL; END;
    DELETE FROM ubicacion WHERE id_ubicacion = l;
    IF EXISTS (SELECT FROM actividad WHERE id_ubicacion = l)
       OR EXISTS (SELECT FROM alarma_recordatorio WHERE id_actividad = a) THEN
        RAISE EXCEPTION 'FALLO: cascada ubicacion/actividad/alarma'; END IF;

    INSERT INTO recuperacion_contrasena (id_usuario, token_recuperacion, fecha_expiracion)
    VALUES (u, 'hash-prueba-' || txid_current(), clock_timestamp() + interval '15 minutes')
    RETURNING id_recuperacion INTO r;
    IF canjear_token('hash-prueba-' || txid_current()) IS DISTINCT FROM u THEN
        RAISE EXCEPTION 'FALLO: canje'; END IF;
    IF canjear_token('hash-prueba-' || txid_current()) IS NOT NULL THEN
        RAISE EXCEPTION 'FALLO: reutilizacion de token'; END IF;
    BEGIN
        UPDATE recuperacion_contrasena SET estado_recuperacion = 'PENDIENTE', fecha_utilizacion = NULL
        WHERE id_recuperacion = r;
        RAISE EXCEPTION 'FALLO: reabrir token';
    EXCEPTION WHEN check_violation THEN NULL; END;
    INSERT INTO recuperacion_contrasena (id_usuario, token_recuperacion, fecha_solicitud, fecha_expiracion)
    VALUES (u, 'hash-expirado-' || txid_current(), clock_timestamp() - interval '1 hour',
            clock_timestamp() - interval '30 minutes');
    IF canjear_token('hash-expirado-' || txid_current()) IS NOT NULL THEN
        RAISE EXCEPTION 'FALLO: token expirado'; END IF;
    DELETE FROM usuarios WHERE id_usuario = u;
    IF EXISTS (SELECT FROM ubicacion WHERE id_usuario = u)
       OR EXISTS (SELECT FROM recuperacion_contrasena WHERE id_usuario = u) THEN
        RAISE EXCEPTION 'FALLO: cascada usuario'; END IF;
    RAISE NOTICE 'OK: relaciones, cascadas, cache, horarios, restricciones y recuperacion';
END;
$$;
ROLLBACK;
