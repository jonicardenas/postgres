\set ON_ERROR_STOP on

SET TIME ZONE 'America/Bogota';
SET search_path TO biblioteca;

-- 1. Evidencia antes de migrar
-- En devolucion no hay préstamos con más de una devolución (0 filas)
SELECT "FK_id_prestamo", count(*)
FROM devolucion
GROUP BY "FK_id_prestamo"
HAVING count(*) > 1;

-- En prestamo no hay filas repetidas para el mismo usuario, libro y fecha (0 filas)
SELECT "FK_id_usuario", "FK_id_libro", "fecha_prestamo", count(*)
FROM prestamo
GROUP BY "FK_id_usuario", "FK_id_libro", "fecha_prestamo"
HAVING count(*) > 1;

-- En ejemplares ningún registro usa el estado 'prestado', aunque hay 17 préstamos abiertos
SELECT (SELECT count(*) FROM ejemplares WHERE "estado" = 'prestado') AS marcados_prestados,
       (SELECT count(*) FROM prestamo p
         WHERE NOT EXISTS (SELECT 1 FROM devolucion d
                            WHERE d."FK_id_prestamo" = p."PK_id_prestamo")) AS prestamos_abiertos;

-- Libros cuyo ejemplares_disponibles no coincide con (copias - préstamos abiertos)
SELECT l."PK_id_libro", l."titulo", l."ejemplares_disponibles" AS guardado,
       (SELECT count(*) FROM ejemplares e WHERE e."FK_id_libro" = l."PK_id_libro")
     - (SELECT count(*) FROM prestamo p
         WHERE p."FK_id_libro" = l."PK_id_libro"
           AND NOT EXISTS (SELECT 1 FROM devolucion d
                            WHERE d."FK_id_prestamo" = p."PK_id_prestamo")) AS calculado
FROM libro l
WHERE l."ejemplares_disponibles" <>
      (SELECT count(*) FROM ejemplares e WHERE e."FK_id_libro" = l."PK_id_libro")
    - (SELECT count(*) FROM prestamo p
        WHERE p."FK_id_libro" = l."PK_id_libro"
          AND NOT EXISTS (SELECT 1 FROM devolucion d
                           WHERE d."FK_id_prestamo" = p."PK_id_prestamo"))
ORDER BY l."PK_id_libro";

-- Préstamos cuyo estado_prestamo guardado no coincide con la devolución o fecha_vencimiento
SELECT p."PK_id_prestamo", p."fecha_vencimiento", p."estado_prestamo" AS guardado,
       CASE
         WHEN d."FK_id_prestamo" IS NOT NULL THEN 'devuelto'
         WHEN p."fecha_vencimiento" < CURRENT_DATE THEN 'vencido'
         ELSE 'activo'
       END AS calculado
FROM prestamo p
LEFT JOIN devolucion d ON d."FK_id_prestamo" = p."PK_id_prestamo"
WHERE p."estado_prestamo" <> CASE
         WHEN d."FK_id_prestamo" IS NOT NULL THEN 'devuelto'
         WHEN p."fecha_vencimiento" < CURRENT_DATE THEN 'vencido'
         ELSE 'activo'
       END
ORDER BY p."PK_id_prestamo";

-- Conteos antes de la migración
SELECT (SELECT count(*) FROM rol) AS roles,
       (SELECT count(*) FROM usuario) AS usuarios,
       (SELECT count(*) FROM libro) AS libros,
       (SELECT count(*) FROM ejemplares) AS ejemplares,
       (SELECT count(*) FROM prestamo) AS prestamos,
       (SELECT count(*) FROM devolucion) AS devoluciones;

-- 2. Migración
BEGIN;

-- devolucion pasa de 1FN a 3FN / FNBC: un préstamo tiene como máximo una devolución
ALTER TABLE devolucion
  DROP CONSTRAINT pk_devolucion,
  ADD CONSTRAINT pk_devolucion PRIMARY KEY ("FK_id_prestamo");

-- ejemplares.estado se reserva solo para condición física
UPDATE ejemplares
SET "estado" = 'disponible'
WHERE "estado" = 'prestado';

ALTER TABLE ejemplares
  DROP CONSTRAINT ck_ejemplares_estado,
  ADD CONSTRAINT ck_ejemplares_estado
    CHECK ("estado" IN ('disponible', 'danado', 'mantenimiento'));

-- proteger la clave candidata natural en prestamo
ALTER TABLE prestamo
  DROP CONSTRAINT IF EXISTS uq_prestamo_usuario_libro_fecha,
  ADD CONSTRAINT uq_prestamo_usuario_libro_fecha
    UNIQUE ("FK_id_usuario", "FK_id_libro", "fecha_prestamo");

-- actualizar datos derivados desfasados
UPDATE libro l
SET "ejemplares_disponibles" =
      (SELECT count(*) FROM ejemplares e WHERE e."FK_id_libro" = l."PK_id_libro")
    - (SELECT count(*) FROM prestamo p
        WHERE p."FK_id_libro" = l."PK_id_libro"
          AND NOT EXISTS (SELECT 1 FROM devolucion d
                           WHERE d."FK_id_prestamo" = p."PK_id_prestamo"))
WHERE l."ejemplares_disponibles" <>
      (SELECT count(*) FROM ejemplares e WHERE e."FK_id_libro" = l."PK_id_libro")
    - (SELECT count(*) FROM prestamo p
        WHERE p."FK_id_libro" = l."PK_id_libro"
          AND NOT EXISTS (SELECT 1 FROM devolucion d
                           WHERE d."FK_id_prestamo" = p."PK_id_prestamo"));

UPDATE prestamo p
SET "estado_prestamo" = CASE
      WHEN EXISTS (SELECT 1 FROM devolucion d
                    WHERE d."FK_id_prestamo" = p."PK_id_prestamo") THEN 'devuelto'
      WHEN p."fecha_vencimiento" < CURRENT_DATE THEN 'vencido'
      ELSE 'activo'
    END
WHERE p."estado_prestamo" <> CASE
      WHEN EXISTS (SELECT 1 FROM devolucion d
                    WHERE d."FK_id_prestamo" = p."PK_id_prestamo") THEN 'devuelto'
      WHEN p."fecha_vencimiento" < CURRENT_DATE THEN 'vencido'
      ELSE 'activo'
    END;

-- vistas para revisar descuadres (0 filas = todo bien)
DROP VIEW IF EXISTS v_descuadre_disponibles, v_descuadre_estado_prestamo;

CREATE VIEW v_descuadre_disponibles AS
SELECT * FROM (
  SELECT l."PK_id_libro",
         l."ejemplares_disponibles" AS guardado,
         (SELECT count(*) FROM ejemplares e
           WHERE e."FK_id_libro" = l."PK_id_libro")
       - (SELECT count(*) FROM prestamo p
           WHERE p."FK_id_libro" = l."PK_id_libro"
             AND NOT EXISTS (SELECT 1 FROM devolucion d
                              WHERE d."FK_id_prestamo" = p."PK_id_prestamo")) AS calculado
  FROM libro l
) t
WHERE guardado <> calculado;

CREATE VIEW v_descuadre_estado_prestamo AS
SELECT p."PK_id_prestamo",
       p."estado_prestamo" AS guardado,
       CASE
         WHEN d."FK_id_prestamo" IS NOT NULL THEN 'devuelto'
         WHEN p."fecha_vencimiento" < CURRENT_DATE THEN 'vencido'
         ELSE 'activo'
       END AS calculado
FROM prestamo p
LEFT JOIN devolucion d ON d."FK_id_prestamo" = p."PK_id_prestamo"
WHERE p."estado_prestamo" <> CASE
         WHEN d."FK_id_prestamo" IS NOT NULL THEN 'devuelto'
         WHEN p."fecha_vencimiento" < CURRENT_DATE THEN 'vencido'
         ELSE 'activo'
       END;

-- 3. Verificación después de migrar
SELECT (SELECT count(*) FROM rol) AS roles,
       (SELECT count(*) FROM usuario) AS usuarios,
       (SELECT count(*) FROM libro) AS libros,
       (SELECT count(*) FROM ejemplares) AS ejemplares,
       (SELECT count(*) FROM prestamo) AS prestamos,
       (SELECT count(*) FROM devolucion) AS devoluciones;

SELECT * FROM v_descuadre_disponibles;
SELECT * FROM v_descuadre_estado_prestamo;

COMMIT;
