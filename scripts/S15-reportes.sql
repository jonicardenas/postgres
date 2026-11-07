-- S15. Los cuatro reportes del proyecto aplicados al esquema biblioteca.
--
-- El profesor muestra los reportes sobre un esquema mínimo. Aquí se
-- reescriben sobre el esquema propio creado por init/01_esquema.sql.
--
-- Uso:
--   docker compose exec postgres psql -U curso -d curso \
--     -f /scripts/S15-reportes-demo.sql
--
-- Equivalencias con nuestro esquema:
--   lector.documento       -> usuario.documento
--   prestamo.documento     -> prestamo.FK_id_usuario
--   prestamo.isbn          -> prestamo.FK_id_libro -> libro
--   fecha_esperada         -> fecha_vencimiento
--   fecha_devolucion NULL  -> no existe fila en devolucion

\set ON_ERROR_STOP on

SET search_path TO biblioteca;

-- ---------------------------------------------------------------
-- Datos de prueba S15: 15 préstamos relativos a CURRENT_DATE.
-- Se insertan solo si aún no existe el mismo préstamo, por lo que el
-- script se puede ejecutar varias veces sin duplicar la demostración.
-- ---------------------------------------------------------------

DO $$
DECLARE
    fila record;
    id_usuario integer;
    id_libro integer;
    id_prestamo integer;
BEGIN
    FOR fila IN
        SELECT *
        FROM (VALUES
            -- Mariana: tres libros devueltos.
            ('9780000000001', '1000000001', 120, 110),
            ('9780000000004', '1000000001', 100,  90),
            ('9780000000007', '1000000001',  80,  70),
            -- Santiago: tres devueltos; uno fue devuelto tarde.
            ('9780000000001', '1000000002',  95,  85),
            ('9780000000005', '1000000002',  75,  65),
            ('9780000000009', '1000000002',  60,  40),
            -- Valentina: una devuelta, una mora y una a tiempo.
            ('9780000000001', '1000000003',  70,  60),
            ('9780000000010', '1000000003',  30, NULL),
            ('9780000000003', '1000000003',   5, NULL),
            -- Juan David: tres abiertas; dos en mora y una vence hoy.
            ('9780000000001', '1000000004',  20, NULL),
            ('9780000000004', '1000000004',  14, NULL),
            ('9780000000007', '1000000004',  40, NULL),
            -- Camila: dos devueltas y una abierta en mora.
            ('9780000000004', '1000000005',  50,  45),
            ('9780000000011', '1000000005',  35,  30),
            ('9780000000005', '1000000005',  16, NULL)
        ) AS datos(isbn, documento, dias_prestamo, dias_devolucion)
    LOOP
        SELECT "PK_id_usuario"
        INTO id_usuario
        FROM biblioteca.usuario
        WHERE "documento" = fila.documento;

        SELECT "PK_id_libro"
        INTO id_libro
        FROM biblioteca.libro
        WHERE "isbn" = fila.isbn;

        IF id_usuario IS NULL OR id_libro IS NULL THEN
            RAISE EXCEPTION 'Falta el usuario % o el libro % para los datos S15',
                fila.documento, fila.isbn;
        END IF;

        SELECT "PK_id_prestamo"
        INTO id_prestamo
        FROM biblioteca.prestamo
        WHERE "FK_id_usuario" = id_usuario
          AND "FK_id_libro" = id_libro
          AND "fecha_prestamo" = CURRENT_DATE - fila.dias_prestamo;

        IF id_prestamo IS NULL THEN
            INSERT INTO biblioteca.prestamo (
                "FK_id_usuario",
                "FK_id_libro",
                "fecha_prestamo",
                "fecha_vencimiento",
                "estado_prestamo"
            )
            VALUES (
                id_usuario,
                id_libro,
                CURRENT_DATE - fila.dias_prestamo,
                CURRENT_DATE - fila.dias_prestamo + 14,
                CASE
                    WHEN fila.dias_devolucion IS NOT NULL THEN 'devuelto'
                    WHEN CURRENT_DATE - fila.dias_prestamo + 14 < CURRENT_DATE
                        THEN 'vencido'
                    ELSE 'activo'
                END
            )
            RETURNING "PK_id_prestamo" INTO id_prestamo;
        END IF;

        IF fila.dias_devolucion IS NOT NULL
           AND NOT EXISTS (
               SELECT 1
               FROM biblioteca.devolucion
               WHERE "FK_id_prestamo" = id_prestamo
           )
        THEN
            INSERT INTO biblioteca.devolucion (
                "FK_id_prestamo",
                "estado_devolucion",
                "fecha_devolucion"
            )
            VALUES (
                id_prestamo,
                CASE
                    WHEN CURRENT_DATE - fila.dias_devolucion
                         > CURRENT_DATE - fila.dias_prestamo + 14
                        THEN 'tardia'
                    ELSE 'a_tiempo'
                END,
                CURRENT_DATE - fila.dias_devolucion
            );
        END IF;
    END LOOP;
END $$;

\echo
\echo '== Reporte 1. Los 20 libros más prestados (incluye empates) =='
SELECT   l."titulo", count(p."PK_id_prestamo") AS prestamos
FROM     biblioteca.libro l
LEFT JOIN biblioteca.prestamo p ON p."FK_id_libro" = l."PK_id_libro"
GROUP BY l."PK_id_libro", l."titulo"
ORDER BY prestamos DESC
FETCH FIRST 20 ROWS WITH TIES;

\echo
\echo '== Reporte 2. El o los lectores que más libros han leído =='
WITH leidos AS (
    SELECT   p."FK_id_usuario" AS id_usuario,
             count(DISTINCT p."PK_id_prestamo") AS devueltos
    FROM     biblioteca.prestamo p
    JOIN     biblioteca.devolucion d
           ON d."FK_id_prestamo" = p."PK_id_prestamo"
    GROUP BY p."FK_id_usuario"
)
SELECT u."nombres",
       u."apellidos",
       x.devueltos
FROM   leidos x
JOIN   biblioteca.usuario u
       ON u."PK_id_usuario" = x.id_usuario
JOIN   biblioteca.rol r
       ON r."PK_id_rol" = u."FK_id_rol"
WHERE  x.devueltos = (SELECT max(devueltos) FROM leidos)
  AND  lower(r."nombre_rol") = 'lector'
ORDER BY u."apellidos";

\echo
\echo '== Reporte 3. Lectores morosos =='
SELECT u."documento",
       u."nombres",
       u."apellidos"
FROM   biblioteca.usuario u
JOIN   biblioteca.rol r
       ON r."PK_id_rol" = u."FK_id_rol"
WHERE  lower(r."nombre_rol") = 'lector'
  AND  EXISTS (
           SELECT 1
           FROM   biblioteca.prestamo p
           WHERE  p."FK_id_usuario" = u."PK_id_usuario"
             AND  p."fecha_vencimiento" < CURRENT_DATE
             AND  NOT EXISTS (
                      SELECT 1
                      FROM   biblioteca.devolucion d
                      WHERE  d."FK_id_prestamo" = p."PK_id_prestamo"
                  )
       )
ORDER BY u."apellidos";

\echo
\echo '== Reporte 4. Préstamos en mora (para la lista de notificación) =='
SELECT u."nombres" || ' ' || u."apellidos" AS lector,
       u."correo",
       u."telefono",
       l."titulo",
       p."fecha_vencimiento",
       CURRENT_DATE - p."fecha_vencimiento" AS dias_mora
FROM   biblioteca.prestamo p
JOIN   biblioteca.usuario u
       ON u."PK_id_usuario" = p."FK_id_usuario"
JOIN   biblioteca.rol r
       ON r."PK_id_rol" = u."FK_id_rol"
JOIN   biblioteca.libro l
       ON l."PK_id_libro" = p."FK_id_libro"
WHERE  lower(r."nombre_rol") = 'lector'
  AND  p."fecha_vencimiento" < CURRENT_DATE
  AND  NOT EXISTS (
           SELECT 1
           FROM   biblioteca.devolucion d
           WHERE  d."FK_id_prestamo" = p."PK_id_prestamo"
       )
ORDER BY dias_mora DESC;
