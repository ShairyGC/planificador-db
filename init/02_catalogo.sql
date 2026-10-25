-- Datos iniciales propuestos; el PDF solo da Senderismo como ejemplo.
BEGIN;
INSERT INTO categoria_pasatiempos (nombre_categoria, icono_referencia) VALUES
    ('Senderismo', 'hiking'),
    ('Deporte', 'sports'),
    ('Lectura', 'book'),
    ('Cine', 'movie'),
    ('Gastronomia', 'restaurant'),
    ('Otros', 'category')
ON CONFLICT (nombre_categoria) DO NOTHING;
COMMIT;
