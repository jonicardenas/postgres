-- ============================================================
-- S16 - REPORTES DE LA BIBLIOTECA
-- Esquema: biblioteca
-- Zona horaria: America/Bogota
-- ============================================================

SET TIME ZONE 'America/Bogota';


-- ============================================================
-- REPORTE 1: TOP 20 LIBROS MAS PRESTADOS
-- Cuenta los prestamos por libro y ordena de mayor a menor.
-- Los libros sin prestamos no aparecen.
-- ============================================================

SELECT
    l."PK_id_libro" AS id_libro,
    l.titulo,
    l.autor,
    COUNT(p."PK_id_prestamo") AS total_prestamos
FROM biblioteca.libro l
INNER JOIN biblioteca.prestamo p
    ON p."FK_id_libro" = l."PK_id_libro"
GROUP BY
    l."PK_id_libro",
    l.titulo,
    l.autor
ORDER BY
    total_prestamos DESC,
    l.titulo ASC
LIMIT 20;


-- ============================================================
-- REPORTE 2: LECTORES CON MAS LIBROS LEIDOS
-- Cuenta las devoluciones registradas y conserva los empates.
-- ============================================================

WITH libros_leidos AS (
    SELECT
        u."PK_id_usuario" AS id_usuario,
        u.nombres,
        u.apellidos,
        COUNT(d."FK_id_prestamo") AS total_libros_leidos
    FROM biblioteca.usuario u
    INNER JOIN biblioteca.prestamo p
        ON p."FK_id_usuario" = u."PK_id_usuario"
    INNER JOIN biblioteca.devolucion d
        ON d."FK_id_prestamo" = p."PK_id_prestamo"
    GROUP BY
        u."PK_id_usuario",
        u.nombres,
        u.apellidos
)
SELECT
    id_usuario,
    nombres,
    apellidos,
    total_libros_leidos
FROM libros_leidos
WHERE total_libros_leidos = (
    SELECT MAX(total_libros_leidos)
    FROM libros_leidos
)
ORDER BY id_usuario;


-- ============================================================
-- REPORTE 3: LECTORES MOROSOS
-- Cada lector aparece una sola vez, aunque tenga varios
-- prestamos vencidos sin devolver.
-- ============================================================

SELECT
    u."PK_id_usuario" AS id_usuario,
    u.nombres,
    u.apellidos,
    u.correo,
    u.telefono
FROM biblioteca.usuario u
WHERE EXISTS (
    SELECT 1
    FROM biblioteca.prestamo p
    WHERE p."FK_id_usuario" = u."PK_id_usuario"
      AND p.estado_prestamo = 'vencido'
      AND NOT EXISTS (
          SELECT 1
          FROM biblioteca.devolucion d
          WHERE d."FK_id_prestamo" = p."PK_id_prestamo"
      )
)
ORDER BY u."PK_id_usuario";


-- ============================================================
-- REPORTE 4: DETALLE DE PRESTAMOS VENCIDOS
-- Incluye datos del libro, lector y dias de retraso.
-- Excluye prestamos devueltos y los que vencen hoy.
-- ============================================================

SELECT
    p."PK_id_prestamo" AS id_prestamo,
    l.titulo AS libro,
    u."PK_id_usuario" AS id_usuario,
    u.nombres,
    u.apellidos,
    u.correo,
    u.telefono,
    p.fecha_prestamo,
    p.fecha_vencimiento,
    CURRENT_DATE - p.fecha_vencimiento AS dias_retraso
FROM biblioteca.prestamo p
INNER JOIN biblioteca.usuario u
    ON u."PK_id_usuario" = p."FK_id_usuario"
INNER JOIN biblioteca.libro l
    ON l."PK_id_libro" = p."FK_id_libro"
WHERE p.estado_prestamo = 'vencido'
  AND NOT EXISTS (
      SELECT 1
      FROM biblioteca.devolucion d
      WHERE d."FK_id_prestamo" = p."PK_id_prestamo"
  )
ORDER BY
    p.fecha_vencimiento ASC,
    u."PK_id_usuario" ASC;


-- ============================================================
-- FIN DE LOS REPORTES S16
-- ============================================================
