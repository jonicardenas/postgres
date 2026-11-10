-- ============================================================
-- S16 - PARTE B: DATOS DE PRUEBA
-- Esquema: biblioteca
--
-- Requisito previo:
-- Ejecutar sobre una base que ya tenga cargados los lectores
-- y los libros semilla.
--
-- Incluye:
-- 31 prestamos y 14 devoluciones.
-- Fechas relativas a CURRENT_DATE para mantener vigentes
-- los escenarios durante la sustentacion.
--
-- IMPORTANTE:
-- No ejecutar si biblioteca.prestamo o biblioteca.devolucion
-- ya contienen registros.
-- ============================================================

BEGIN;

SET LOCAL TIME ZONE 'America/Bogota';

-- ------------------------------------------------------------
-- 1. Validaciones previas.
-- ------------------------------------------------------------

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM biblioteca.prestamo)
       OR EXISTS (SELECT 1 FROM biblioteca.devolucion) THEN
        RAISE EXCEPTION
            'Las tablas prestamo o devolucion ya contienen datos. Se cancela la carga.';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM biblioteca.usuario
        WHERE "PK_id_usuario" BETWEEN 1 AND 10
    ) <> 10 THEN
        RAISE EXCEPTION
            'No se encontraron los diez lectores requeridos (IDs 1-10).';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM biblioteca.libro
        WHERE "PK_id_libro" BETWEEN 1 AND 21
    ) <> 21 THEN
        RAISE EXCEPTION
            'No se encontraron los 21 libros requeridos (IDs 1-21).';
    END IF;
END $$;


-- ------------------------------------------------------------
-- 2. Prestamos de prueba.
--
-- Los desplazamientos de fecha se calculan desde CURRENT_DATE.
-- Los IDs 1039-1045 corresponden a los siete prestamos
-- adicionales para probar el empate en el limite del top 20.
-- ------------------------------------------------------------

INSERT INTO biblioteca.prestamo (
    "PK_id_prestamo",
    "FK_id_usuario",
    "FK_id_libro",
    fecha_prestamo,
    fecha_vencimiento,
    estado_prestamo
)
VALUES
    (1001, 1,  1, CURRENT_DATE - 50, CURRENT_DATE - 39, 'devuelto'),
    (1002, 1,  2, CURRENT_DATE - 45, CURRENT_DATE - 35, 'devuelto'),
    (1003, 1,  3, CURRENT_DATE - 39, CURRENT_DATE - 30, 'devuelto'),
    (1004, 1,  4, CURRENT_DATE - 30, CURRENT_DATE - 20, 'devuelto'),
    (1005, 1,  1, CURRENT_DATE - 20, CURRENT_DATE -  8, 'vencido'),
    (1006, 1,  2, CURRENT_DATE - 18, CURRENT_DATE -  6, 'vencido'),
    (1007, 1,  5, CURRENT_DATE -  8, CURRENT_DATE,      'activo'),

    (1008, 2,  1, CURRENT_DATE - 48, CURRENT_DATE - 38, 'devuelto'),
    (1009, 2,  2, CURRENT_DATE - 43, CURRENT_DATE - 33, 'devuelto'),
    (1010, 2,  3, CURRENT_DATE - 38, CURRENT_DATE - 28, 'devuelto'),
    (1011, 2,  6, CURRENT_DATE - 28, CURRENT_DATE - 18, 'devuelto'),

    (1012, 3,  1, CURRENT_DATE -  8, CURRENT_DATE + 11, 'activo'),
    (1013, 3,  2, CURRENT_DATE -  7, CURRENT_DATE + 16, 'activo'),

    (1014, 4,  4, CURRENT_DATE - 25, CURRENT_DATE - 15, 'devuelto'),
    (1015, 4,  5, CURRENT_DATE - 22, CURRENT_DATE - 12, 'devuelto'),
    (1016, 4,  7, CURRENT_DATE - 16, CURRENT_DATE -  5, 'vencido'),
    (1017, 4,  8, CURRENT_DATE - 15, CURRENT_DATE -  4, 'vencido'),

    (1018, 6,  1, CURRENT_DATE - 20, CURRENT_DATE - 10, 'devuelto'),
    (1019, 6,  9, CURRENT_DATE - 18, CURRENT_DATE -  8, 'devuelto'),
    (1020, 6, 10, CURRENT_DATE - 17, CURRENT_DATE -  7, 'devuelto'),

    (1021, 7, 11, CURRENT_DATE -  6, CURRENT_DATE,      'activo'),
    (1022, 8, 12, CURRENT_DATE - 12, CURRENT_DATE -  1, 'vencido'),
    (1023, 9, 13, CURRENT_DATE - 20, CURRENT_DATE -  8, 'devuelto'),
    (1024,10, 14, CURRENT_DATE -  8, CURRENT_DATE + 21, 'activo'),

    -- Siete prestamos adicionales para el empate del top 20.
    (1039, 3, 15, CURRENT_DATE -  1, CURRENT_DATE + 14, 'activo'),
    (1040, 3, 16, CURRENT_DATE -  1, CURRENT_DATE + 14, 'activo'),
    (1041, 3, 17, CURRENT_DATE -  1, CURRENT_DATE + 14, 'activo'),
    (1042, 3, 18, CURRENT_DATE -  1, CURRENT_DATE + 14, 'activo'),
    (1043, 3, 19, CURRENT_DATE -  1, CURRENT_DATE + 14, 'activo'),
    (1044, 3, 20, CURRENT_DATE -  1, CURRENT_DATE + 14, 'activo'),
    (1045, 3, 21, CURRENT_DATE -  1, CURRENT_DATE + 14, 'activo');


-- ------------------------------------------------------------
-- 3. Devoluciones de prueba.
--
-- Los préstamos 1003 y 1023 fueron devueltos tarde.
-- Los demás registros de devolución corresponden a entregas
-- a tiempo.
-- ------------------------------------------------------------

INSERT INTO biblioteca.devolucion (
    "FK_id_prestamo",
    "FK_id_ejemplar",
    estado_devolucion,
    fecha_devolucion
)
SELECT
    d.id_prestamo,
    e."PK_id_ejemplar",
    d.estado_devolucion,
    d.fecha_devolucion
FROM (
    VALUES
        (1001, 'a_tiempo'::varchar, CURRENT_DATE - 42, 1),
        (1002, 'a_tiempo'::varchar, CURRENT_DATE - 35, 2),
        (1003, 'tardia'::varchar,   CURRENT_DATE - 25, 3),
        (1004, 'a_tiempo'::varchar, CURRENT_DATE - 21, 4),
        (1008, 'a_tiempo'::varchar, CURRENT_DATE - 39, 1),
        (1009, 'a_tiempo'::varchar, CURRENT_DATE - 34, 2),
        (1010, 'a_tiempo'::varchar, CURRENT_DATE - 29, 3),
        (1011, 'a_tiempo'::varchar, CURRENT_DATE - 20, 6),
        (1014, 'a_tiempo'::varchar, CURRENT_DATE - 16, 4),
        (1015, 'a_tiempo'::varchar, CURRENT_DATE - 13, 5),
        (1018, 'a_tiempo'::varchar, CURRENT_DATE - 11, 1),
        (1019, 'a_tiempo'::varchar, CURRENT_DATE -  9, 9),
        (1020, 'a_tiempo'::varchar, CURRENT_DATE -  8, 10),
        (1023, 'tardia'::varchar,   CURRENT_DATE -  4, 13)
) AS d(id_prestamo, estado_devolucion, fecha_devolucion, id_libro)
JOIN biblioteca.ejemplares e
    ON e."FK_id_libro" = d.id_libro
   AND e."PK_id_ejemplar" = (
       SELECT MIN(e2."PK_id_ejemplar")
       FROM biblioteca.ejemplares e2
       WHERE e2."FK_id_libro" = d.id_libro
   );


-- ------------------------------------------------------------
-- 4. Sincronizar las secuencias de identidad.
-- ------------------------------------------------------------

SELECT setval(
    pg_get_serial_sequence(
        'biblioteca.prestamo',
        'PK_id_prestamo'
    ),
    (SELECT MAX("PK_id_prestamo") FROM biblioteca.prestamo),
    true
);

-- ------------------------------------------------------------
-- 5. Confirmar la carga.
-- ------------------------------------------------------------

COMMIT;

SELECT
    COUNT(*) AS total_prestamos,
    COUNT(*) FILTER (WHERE estado_prestamo = 'activo') AS activos,
    COUNT(*) FILTER (WHERE estado_prestamo = 'devuelto') AS devueltos,
    COUNT(*) FILTER (WHERE estado_prestamo = 'vencido') AS vencidos
FROM biblioteca.prestamo;

SELECT
    COUNT(*) AS total_devoluciones,
    COUNT(*) FILTER (
        WHERE estado_devolucion = 'tardia'
    ) AS devoluciones_tardias
FROM biblioteca.devolucion;
