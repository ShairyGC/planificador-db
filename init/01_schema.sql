-- Modelo del PDF "Diseno de Base de Datos: Planificador de Actividades".
-- Ejecutado una sola vez, al inicializar un volumen vacio.
BEGIN;
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TYPE estado_usuario_enum AS ENUM ('ACTIVO', 'BLOQUEADO', 'INACTIVO');
CREATE TYPE estado_recuperacion_enum AS ENUM ('PENDIENTE', 'UTILIZADO', 'EXPIRADO');
CREATE TYPE origen_ubicacion_enum AS ENUM ('GPS_MANUAL', 'GOOGLE_PLACES');
CREATE TYPE tipo_entorno_enum AS ENUM ('INDOOR', 'OUTDOOR');
CREATE TYPE estado_actividad_enum AS ENUM ('PENDIENTE', 'REALIZADA', 'CANCELADA');
CREATE TYPE estado_alarma_enum AS ENUM ('PENDIENTE', 'ENVIADA');

CREATE TABLE usuarios (
    id_usuario bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombres varchar(150) NOT NULL,
    apellidos varchar(150) NOT NULL,
    correo_electronico varchar(254) NOT NULL UNIQUE,
    telefono varchar(30),
    nombre_usuario varchar(80) NOT NULL UNIQUE,
    password_hash varchar(255) NOT NULL,
    es_password_temporal boolean NOT NULL DEFAULT false,
    estado_usuario estado_usuario_enum NOT NULL DEFAULT 'ACTIVO',
    fecha_registro timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE recuperacion_contrasena (
    id_recuperacion bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_usuario bigint NOT NULL REFERENCES usuarios ON DELETE CASCADE,
    token_recuperacion varchar(255) NOT NULL UNIQUE,
    fecha_solicitud timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_expiracion timestamptz NOT NULL,
    fecha_utilizacion timestamptz,
    estado_recuperacion estado_recuperacion_enum NOT NULL DEFAULT 'PENDIENTE',
    CONSTRAINT recuperacion_fechas_validas CHECK (fecha_expiracion > fecha_solicitud),
    CONSTRAINT recuperacion_uso_valido CHECK (
        (estado_recuperacion = 'UTILIZADO' AND fecha_utilizacion IS NOT NULL
         AND fecha_utilizacion >= fecha_solicitud AND fecha_utilizacion < fecha_expiracion)
        OR (estado_recuperacion <> 'UTILIZADO' AND fecha_utilizacion IS NULL)
    )
);

CREATE TABLE ubicacion (
    id_ubicacion bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_usuario bigint NOT NULL REFERENCES usuarios ON DELETE CASCADE,
    nombre_lugar varchar(200) NOT NULL,
    direccion_formateada varchar(500) NOT NULL,
    latitud numeric(10,7) NOT NULL CHECK (latitud BETWEEN -90 AND 90),
    longitud numeric(10,7) NOT NULL CHECK (longitud BETWEEN -180 AND 180),
    notas_ubicacion text,
    origen_ubicacion origen_ubicacion_enum NOT NULL,
    google_place_id varchar(255) UNIQUE,
    visitas_acumuladas integer NOT NULL DEFAULT 0 CHECK (visitas_acumuladas >= 0),
    calificacion_promedio numeric(4,2) NOT NULL DEFAULT 0.0
        CHECK (calificacion_promedio BETWEEN 0 AND 5),
    fecha_creacion timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (id_ubicacion, id_usuario)
);

CREATE TABLE categoria_pasatiempos (
    id_categoria bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_categoria varchar(100) NOT NULL UNIQUE,
    icono_referencia varchar(100)
);

CREATE TABLE actividad (
    id_actividad bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_usuario bigint NOT NULL REFERENCES usuarios ON DELETE CASCADE,
    id_ubicacion bigint NOT NULL,
    id_categoria bigint REFERENCES categoria_pasatiempos ON DELETE SET NULL,
    titulo_actividad varchar(200) NOT NULL,
    fecha_hora_inicio timestamptz NOT NULL,
    fecha_hora_fin timestamptz NOT NULL,
    tipo_entorno tipo_entorno_enum NOT NULL,
    condicion_clima_deseable varchar(150),
    detalles_reunion text,
    estado_actividad estado_actividad_enum NOT NULL DEFAULT 'PENDIENTE',
    calificacion_nps integer CHECK (calificacion_nps BETWEEN 1 AND 5),
    comentario_experiencia text,
    fecha_creacion timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT actividad_ubicacion_del_usuario FOREIGN KEY (id_ubicacion, id_usuario)
        REFERENCES ubicacion (id_ubicacion, id_usuario) ON DELETE CASCADE,
    CONSTRAINT actividad_fechas_validas CHECK (fecha_hora_fin > fecha_hora_inicio),
    CONSTRAINT actividad_sin_traslape EXCLUDE USING gist (
        id_usuario WITH =,
        tstzrange(fecha_hora_inicio, fecha_hora_fin, '[)') WITH &&
    ) WHERE (estado_actividad <> 'CANCELADA')
);

CREATE TABLE alarma_recordatorio (
    id_alarma bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_actividad bigint NOT NULL REFERENCES actividad ON DELETE CASCADE,
    minutos_anticipacion integer NOT NULL CHECK (minutos_anticipacion >= 0),
    estado_alarma estado_alarma_enum NOT NULL DEFAULT 'PENDIENTE',
    fecha_creacion timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX ON recuperacion_contrasena (id_usuario);
CREATE INDEX ON ubicacion (id_usuario);
CREATE INDEX ON actividad (id_ubicacion, id_usuario);
CREATE INDEX ON actividad (id_categoria);
CREATE INDEX ON actividad (id_usuario, fecha_hora_inicio);
CREATE INDEX ON alarma_recordatorio (id_actividad);

CREATE FUNCTION actualizar_fecha() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.fecha_actualizacion := clock_timestamp();
    RETURN NEW;
END;
$$;
CREATE TRIGGER usuarios_actualizacion BEFORE UPDATE ON usuarios
    FOR EACH ROW EXECUTE FUNCTION actualizar_fecha();
CREATE TRIGGER ubicacion_actualizacion BEFORE UPDATE ON ubicacion
    FOR EACH ROW EXECUTE FUNCTION actualizar_fecha();
CREATE TRIGGER actividad_actualizacion BEFORE UPDATE ON actividad
    FOR EACH ROW EXECUTE FUNCTION actualizar_fecha();

CREATE FUNCTION proteger_nombre_usuario() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.nombre_usuario IS DISTINCT FROM OLD.nombre_usuario THEN
        RAISE EXCEPTION 'El nombre_usuario no puede modificarse' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER usuarios_nombre_inmutable BEFORE UPDATE ON usuarios
    FOR EACH ROW EXECUTE FUNCTION proteger_nombre_usuario();

-- Serializa los cambios de actividades de un mismo lugar para recalcular su cache.
-- Bloqueo NO KEY UPDATE: compatible con las comprobaciones de claves foraneas.
CREATE FUNCTION bloquear_ubicaciones_actividad() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE anterior bigint; nueva bigint;
BEGIN
    IF TG_OP <> 'INSERT' THEN anterior := OLD.id_ubicacion; END IF;
    IF TG_OP <> 'DELETE' THEN nueva := NEW.id_ubicacion; END IF;
    PERFORM id_ubicacion FROM ubicacion
        WHERE id_ubicacion IN (anterior, nueva)
        ORDER BY id_ubicacion FOR NO KEY UPDATE;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER actividad_bloquear_cache BEFORE INSERT OR UPDATE OR DELETE ON actividad
    FOR EACH ROW EXECUTE FUNCTION bloquear_ubicaciones_actividad();

CREATE FUNCTION recalcular_estadisticas_ubicacion() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE anterior bigint; nueva bigint; lugar bigint;
BEGIN
    IF TG_OP <> 'INSERT' THEN anterior := OLD.id_ubicacion; END IF;
    IF TG_OP <> 'DELETE' THEN nueva := NEW.id_ubicacion; END IF;
    FOR lugar IN SELECT DISTINCT id FROM unnest(ARRAY[anterior, nueva]) AS t(id)
                 WHERE id IS NOT NULL ORDER BY id LOOP
        UPDATE ubicacion SET
            visitas_acumuladas = (SELECT count(*) FROM actividad
                WHERE id_ubicacion = lugar AND estado_actividad = 'REALIZADA'),
            calificacion_promedio = (SELECT COALESCE(round(avg(calificacion_nps), 2), 0)
                FROM actividad WHERE id_ubicacion = lugar AND estado_actividad = 'REALIZADA')
        WHERE id_ubicacion = lugar;
    END LOOP;
    RETURN NULL;
END;
$$;
CREATE TRIGGER actividad_estadisticas AFTER INSERT OR UPDATE OR DELETE ON actividad
    FOR EACH ROW EXECUTE FUNCTION recalcular_estadisticas_ubicacion();

CREATE FUNCTION proteger_token_recuperacion() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.estado_recuperacion <> 'PENDIENTE'
       OR NEW.token_recuperacion IS DISTINCT FROM OLD.token_recuperacion
       OR NEW.id_usuario IS DISTINCT FROM OLD.id_usuario
       OR NEW.fecha_solicitud IS DISTINCT FROM OLD.fecha_solicitud
       OR NEW.fecha_expiracion IS DISTINCT FROM OLD.fecha_expiracion THEN
        RAISE EXCEPTION 'No se puede reabrir ni alterar una solicitud de recuperacion'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.estado_recuperacion = 'UTILIZADO' AND clock_timestamp() >= OLD.fecha_expiracion THEN
        RAISE EXCEPTION 'El token ha expirado' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER recuperacion_proteger BEFORE UPDATE ON recuperacion_contrasena
    FOR EACH ROW EXECUTE FUNCTION proteger_token_recuperacion();

-- Recibe el HASH del token. Devuelve el usuario o NULL si ya se uso/no existe/expiro.
-- Ejecutar en la misma transaccion que el cambio de password_hash del backend.
CREATE FUNCTION canjear_token(p_token_hash varchar) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE usuario bigint;
BEGIN
    UPDATE recuperacion_contrasena SET estado_recuperacion = 'UTILIZADO',
        fecha_utilizacion = clock_timestamp()
    WHERE token_recuperacion = p_token_hash AND estado_recuperacion = 'PENDIENTE'
        AND fecha_expiracion > clock_timestamp()
    RETURNING id_usuario INTO usuario;
    RETURN usuario;
END;
$$;
COMMIT;
