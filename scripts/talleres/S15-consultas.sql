-- ============================================================
-- S15 - CONSULTAS AVANZADAS SOBRE MATRICULAS
-- Joins externos, agregacion, subconsultas y division
--
-- Requiere ejecutar previamente S15-matriculas.sql
-- Este archivo solo realiza consultas SELECT.
-- ============================================================

SET search_path TO matriculas;


-- ============================================================
-- 3. JOINS EXTERNOS
-- ============================================================

-- 3.1 INNER JOIN: estudiantes que tienen aprobaciones.
-- Elena no aparece porque no tiene cursos aprobados.

SELECT e.nombre, a.cod_curso, a.nota
FROM estudiante e
JOIN aprobo a ON a.cod_est = e.cod_est
ORDER BY e.nombre, a.cod_curso;


-- 3.2 LEFT JOIN: conserva todos los estudiantes.
-- Elena aparece con NULL en las columnas de aprobo.

SELECT e.nombre, a.cod_curso, a.nota
FROM estudiante e
LEFT JOIN aprobo a ON a.cod_est = e.cod_est
ORDER BY e.nombre, a.cod_curso;


-- RIGHT JOIN: conserva todos los cursos.
-- Seminario aparece aunque nadie lo haya aprobado.

SELECT c.nombre_curso, a.cod_est, a.nota
FROM aprobo a
RIGHT JOIN curso c ON c.cod_curso = a.cod_curso
ORDER BY c.cod_curso, a.cod_est;


-- FULL JOIN: conserva las filas sin pareja de ambos lados.
-- Aparecen Elena y Seminario.

SELECT
    e.nombre,
    a.cod_curso,
    c.nombre_curso,
    a.nota
FROM estudiante e
FULL JOIN aprobo a
    ON a.cod_est = e.cod_est
FULL JOIN curso c
    ON c.cod_curso = a.cod_curso
ORDER BY e.nombre NULLS LAST, c.cod_curso NULLS LAST;


-- 3.3 ANTI-JOIN: estudiantes que no tienen aprobaciones.
-- Resultado esperado: Elena.

SELECT e.nombre
FROM estudiante e
LEFT JOIN aprobo a ON a.cod_est = e.cod_est
WHERE a.cod_est IS NULL;


-- La misma consulta utilizando NOT EXISTS.

SELECT e.nombre
FROM estudiante e
WHERE NOT EXISTS (
    SELECT 1
    FROM aprobo a
    WHERE a.cod_est = e.cod_est
);


-- 3.4 Diferencia entre filtrar en WHERE y en ON.

-- Consulta A: el WHERE elimina estudiantes sin esa aprobación.

SELECT e.nombre, a.nota
FROM estudiante e
LEFT JOIN aprobo a
    ON a.cod_est = e.cod_est
WHERE a.cod_curso = '750006C'
ORDER BY e.nombre;


-- Consulta B: el ON conserva todos los estudiantes.
-- Los que no aprobaron Bases de Datos aparecen con NULL.

SELECT e.nombre, a.nota
FROM estudiante e
LEFT JOIN aprobo a
    ON a.cod_est = e.cod_est
   AND a.cod_curso = '750006C'
ORDER BY e.nombre;


-- ============================================================
-- 4. AGREGACION: GROUP BY Y HAVING
-- ============================================================

-- 4.1 Funciones de agregacion sobre toda la tabla.

SELECT
    COUNT(*) AS cantidad_filas,
    COUNT(DISTINCT cod_est) AS estudiantes_distintos,
    ROUND(AVG(nota), 2) AS promedio,
    MIN(nota) AS nota_minima,
    MAX(nota) AS nota_maxima,
    SUM(nota) AS suma_notas
FROM aprobo;


-- 4.2 Cantidad de cursos aprobados y promedio por estudiante.

SELECT
    cod_est,
    COUNT(*) AS cursos,
    ROUND(AVG(nota), 2) AS promedio
FROM aprobo
GROUP BY cod_est
ORDER BY cod_est;


-- Nombre, cantidad de cursos y creditos aprobados por estudiante.

SELECT
    e.nombre,
    COUNT(*) AS cursos,
    SUM(c.creditos) AS creditos
FROM estudiante e
JOIN aprobo a
    ON a.cod_est = e.cod_est
JOIN curso c
    ON c.cod_curso = a.cod_curso
GROUP BY e.cod_est, e.nombre
ORDER BY creditos DESC;


-- 4.3 Estudiantes con al menos dos cursos aprobados.
-- Resultado esperado: Ana y Diego.

SELECT
    e.nombre,
    ROUND(AVG(a.nota), 2) AS promedio
FROM estudiante e
JOIN aprobo a
    ON a.cod_est = e.cod_est
GROUP BY e.cod_est, e.nombre
HAVING COUNT(*) >= 2
ORDER BY promedio DESC;


-- Cursos con al menos dos aprobaciones de nota >= 3.5.

SELECT
    cod_curso,
    COUNT(*) AS aprobaciones
FROM aprobo
WHERE nota >= 3.5
GROUP BY cod_curso
HAVING COUNT(*) >= 2
ORDER BY cod_curso;


-- Agregado en HAVING que no aparece en SELECT.
-- Resultado esperado: Ana y Carla.

SELECT
    cod_est,
    ROUND(AVG(nota), 2) AS promedio
FROM aprobo
GROUP BY cod_est
HAVING MAX(nota) >= 4.5
ORDER BY cod_est;


-- 4.5 Contar incluyendo estudiantes sin aprobaciones.
-- COUNT(*) cuenta la fila generada por el LEFT JOIN.
-- COUNT(a.cod_curso) ignora el NULL y devuelve cero para Elena.

SELECT
    e.nombre,
    COUNT(*) AS conteo_incorrecto_para_ceros,
    COUNT(a.cod_curso) AS cursos_aprobados
FROM estudiante e
LEFT JOIN aprobo a
    ON a.cod_est = e.cod_est
GROUP BY e.cod_est, e.nombre
ORDER BY e.nombre;


-- ============================================================
-- 5. SUBCONSULTAS
-- ============================================================

-- 5.1 Subconsulta escalar.
-- Notas superiores al promedio general.

SELECT cod_est, cod_curso, nota
FROM aprobo
WHERE nota > (
    SELECT AVG(nota)
    FROM aprobo
)
ORDER BY nota DESC;


-- 5.2 IN: estudiantes que aprobaron Bases de Datos.

SELECT nombre
FROM estudiante
WHERE cod_est IN (
    SELECT cod_est
    FROM aprobo
    WHERE cod_curso = '750006C'
)
ORDER BY nombre;


-- NOT IN: estudiantes que no aprobaron Bases de Datos.

SELECT nombre
FROM estudiante
WHERE cod_est NOT IN (
    SELECT cod_est
    FROM aprobo
    WHERE cod_curso = '750006C'
)
ORDER BY nombre;


-- 5.3 Demostracion de la trampa de NOT IN con NULL.
-- Primera consulta: devuelve Carla y Elena.

SELECT nombre
FROM estudiante
WHERE cod_prog NOT IN (3743)
ORDER BY nombre;


-- Segunda consulta: devuelve cero filas por la presencia de NULL.

SELECT nombre
FROM estudiante
WHERE cod_prog NOT IN (3743, NULL)
ORDER BY nombre;


-- 5.4 EXISTS correlacionado.
-- Estudiantes con al menos una nota de 4.5 o superior.
-- Resultado esperado: Ana y Carla.

SELECT e.nombre
FROM estudiante e
WHERE EXISTS (
    SELECT 1
    FROM aprobo a
    WHERE a.cod_est = e.cod_est
      AND a.nota >= 4.5
)
ORDER BY e.nombre;


-- NOT EXISTS correlacionado.
-- Cursos que nadie ha aprobado.
-- Resultado esperado: Seminario.

SELECT c.nombre_curso
FROM curso c
WHERE NOT EXISTS (
    SELECT 1
    FROM aprobo a
    WHERE a.cod_curso = c.cod_curso
)
ORDER BY c.nombre_curso;


-- Cursos donde nadie obtuvo una nota inferior a 3.5.
-- Seminario aparece porque no tiene ninguna nota.

SELECT c.nombre_curso
FROM curso c
WHERE NOT EXISTS (
    SELECT 1
    FROM aprobo a
    WHERE a.cod_curso = c.cod_curso
      AND a.nota < 3.5
)
ORDER BY c.nombre_curso;


-- 5.5 Subconsulta en FROM.
-- Obtener el promedio mas alto.

SELECT MAX(t.promedio) AS mejor_promedio
FROM (
    SELECT
        cod_est,
        AVG(nota) AS promedio
    FROM aprobo
    GROUP BY cod_est
) AS t;


-- CTE con WITH: estudiante o estudiantes con el mejor promedio.
-- Conserva los empates.

WITH promedios AS (
    SELECT
        cod_est,
        ROUND(AVG(nota), 2) AS promedio
    FROM aprobo
    GROUP BY cod_est
)
SELECT
    e.nombre,
    p.promedio
FROM promedios p
JOIN estudiante e
    ON e.cod_est = p.cod_est
WHERE p.promedio = (
    SELECT MAX(promedio)
    FROM promedios
)
ORDER BY e.nombre;


-- ============================================================
-- 6. DIVISION: APROBAR TODOS LOS CURSOS DE 3 CREDITOS
-- ============================================================

-- 6.1 Solucion con NOT EXISTS doble.
-- Resultado esperado: Ana.

SELECT e.nombre
FROM estudiante e
WHERE NOT EXISTS (
    SELECT 1
    FROM curso c
    WHERE c.creditos = 3
      AND NOT EXISTS (
          SELECT 1
          FROM aprobo a
          WHERE a.cod_est = e.cod_est
            AND a.cod_curso = c.cod_curso
      )
)
ORDER BY e.nombre;


-- 6.2 Alternativa mediante conteo.
-- En este esquema es valida porque aprobo tiene una PK
-- compuesta por cod_est y cod_curso.

SELECT e.nombre
FROM estudiante e
JOIN aprobo a
    ON a.cod_est = e.cod_est
JOIN curso c
    ON c.cod_curso = a.cod_curso
WHERE c.creditos = 3
GROUP BY e.cod_est, e.nombre
HAVING COUNT(*) = (
    SELECT COUNT(*)
    FROM curso
    WHERE creditos = 3
)
ORDER BY e.nombre;


-- 6.3 Divisor vacio.
-- No existen cursos de 5 creditos.
-- NOT EXISTS doble devuelve los cinco estudiantes.

SELECT e.nombre
FROM estudiante e
WHERE NOT EXISTS (
    SELECT 1
    FROM curso c
    WHERE c.creditos = 5
      AND NOT EXISTS (
          SELECT 1
          FROM aprobo a
          WHERE a.cod_est = e.cod_est
            AND a.cod_curso = c.cod_curso
      )
)
ORDER BY e.nombre;


-- ============================================================
-- FIN DE S15-CONSULTAS.SQL
-- ============================================================