-- S16. Parte B: los cuatro reportes del proyecto sobre biblioteca.
--
-- Esta versión parte de scripts/S15-reportes.sql y adapta lo solicitado en S16:
-- - Top 20 parte del catálogo con LEFT JOIN y conserva empates con WITH TIES.
-- - "Libros leídos" son préstamos con devolución y conserva empates con MAX.
-- - Lectores morosos usa EXISTS para que cada lector aparezca una sola vez.
-- - Préstamos en mora lista cada préstamo para notificación con días calculados.
-- - La mora se evalúa dinámicamente con fechas (< CURRENT_DATE y sin devolución).

\set ON_ERROR_STOP on

SET TIME ZONE 'America/Bogota';
SET search_path TO biblioteca;


-- ============================================================
-- Reporte 1: Los 20 libros más prestados (incluye empates)
-- Devuelve: id_libro, titulo, autor, prestamos.
-- Decisiones: LEFT JOIN para incluir catálogo completo (0 préstamos)
-- y FETCH FIRST 20 ROWS WITH TIES para no amputar empates del límite.
-- Esperado: 21 filas (5 con >= 2 préstamos + 16 empatados con 1).
-- ============================================================

\echo
\echo '== Reporte 1. Los 20 libros más prestados (incluye empates) =='
WITH prestamos_por_libro AS (
    SELECT
        l."PK_id_libro" AS id_libro,
        l."titulo" AS titulo,
        l."autor" AS autor,
        COUNT(p."PK_id_prestamo") AS prestamos
    FROM biblioteca.libro l
    LEFT JOIN biblioteca.prestamo p
        ON p."FK_id_libro" = l."PK_id_libro"
    GROUP BY
        l."PK_id_libro",
        l."titulo",
        l."autor"
),
top_20 AS (
    SELECT *
    FROM prestamos_por_libro
    ORDER BY prestamos DESC
    FETCH FIRST 20 ROWS WITH TIES
)
SELECT
    id_libro,
    titulo,
    autor,
    prestamos
FROM top_20
ORDER BY prestamos DESC, titulo ASC;


-- ============================================================
-- Reporte 2: El o los lectores que más libros han leído
-- Devuelve: id_usuario, nombres, apellidos, total_libros_leidos.
-- Decisiones: solo préstamos con devolución registrada; conserva
-- empates comparando con MAX(); filtra usuarios con rol 'lector'.
-- Esperado: 2 filas (Mariana Gómez y Santiago Rodríguez con 4 leídos).
-- ============================================================

\echo
\echo '== Reporte 2. El o los lectores que más libros han leído =='
WITH leidos AS (
    SELECT
        p."FK_id_usuario" AS id_usuario,
        COUNT(DISTINCT p."PK_id_prestamo") AS devueltos
    FROM biblioteca.prestamo p
    JOIN biblioteca.devolucion d
        ON d."FK_id_prestamo" = p."PK_id_prestamo"
    GROUP BY p."FK_id_usuario"
),
maximo AS (
    SELECT MAX(devueltos) AS devueltos
    FROM leidos
)
SELECT
    u."PK_id_usuario" AS id_usuario,
    u."nombres",
    u."apellidos",
    x.devueltos AS total_libros_leidos
FROM leidos x
JOIN maximo m
    ON m.devueltos = x.devueltos
JOIN biblioteca.usuario u
    ON u."PK_id_usuario" = x.id_usuario
JOIN biblioteca.rol r
    ON r."PK_id_rol" = u."FK_id_rol"
WHERE lower(r."nombre_rol") = 'lector'
ORDER BY u."apellidos", u."nombres", u."PK_id_usuario";


-- ============================================================
-- Reporte 3: Lectores morosos
-- Devuelve: documento, nombres, apellidos, correo, telefono.
-- Decisiones: EXISTS garantiza una fila por lector; condición
-- fecha_vencimiento < CURRENT_DATE y sin registro en devolución.
-- Esperado: 3 filas (Mariana Gómez, Juan David Martínez, Andrés Felipe Vargas).
-- ============================================================

\echo
\echo '== Reporte 3. Lectores morosos =='
SELECT
    u."documento",
    u."nombres",
    u."apellidos",
    u."correo",
    u."telefono"
FROM biblioteca.usuario u
JOIN biblioteca.rol r
    ON r."PK_id_rol" = u."FK_id_rol"
WHERE lower(r."nombre_rol") = 'lector'
  AND EXISTS (
      SELECT 1
      FROM biblioteca.prestamo p
      WHERE p."FK_id_usuario" = u."PK_id_usuario"
        AND p."fecha_vencimiento" < CURRENT_DATE
        AND NOT EXISTS (
            SELECT 1
            FROM biblioteca.devolucion d
            WHERE d."FK_id_prestamo" = p."PK_id_prestamo"
        )
  )
ORDER BY u."apellidos", u."nombres", u."PK_id_usuario";


-- ============================================================
-- Reporte 4: Préstamos en mora (lista de notificación)
-- Devuelve: lector, correo, telefono, titulo, fecha_vencimiento, dias_mora.
-- Decisiones: nivel de detalle por préstamo; calcula dias_mora
-- dinámicamente con fechas; ordenado por dias_mora DESC.
-- Esperado: 5 filas (2 de Mariana, 2 de Juan David, 1 de Andrés Felipe).
-- ============================================================

\echo
\echo '== Reporte 4. Préstamos en mora (lista de notificación) =='
SELECT
    u."nombres" || ' ' || u."apellidos" AS lector,
    u."correo",
    u."telefono",
    l."titulo",
    p."fecha_vencimiento",
    CURRENT_DATE - p."fecha_vencimiento" AS dias_mora
FROM biblioteca.prestamo p
JOIN biblioteca.usuario u
    ON u."PK_id_usuario" = p."FK_id_usuario"
JOIN biblioteca.rol r
    ON r."PK_id_rol" = u."FK_id_rol"
JOIN biblioteca.libro l
    ON l."PK_id_libro" = p."FK_id_libro"
WHERE lower(r."nombre_rol") = 'lector'
  AND p."fecha_vencimiento" < CURRENT_DATE
  AND NOT EXISTS (
      SELECT 1
      FROM biblioteca.devolucion d
      WHERE d."FK_id_prestamo" = p."PK_id_prestamo"
  )
ORDER BY dias_mora DESC, u."apellidos", u."nombres", l."titulo";
