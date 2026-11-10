-- S16 - PARTE A: 11 consultas sobre el esquema tienda
-- Requiere haber ejecutado previamente S16-tienda.sql.

\set ON_ERROR_STOP on
SET search_path TO tienda;

-- ===============================================================
-- 1. Pedido 1003: cliente, productos, cantidades y subtotales.
-- Esperado: 2 filas.
-- ===============================================================

SELECT
    c.nombre AS cliente,
    pr.nombre AS producto,
    d.cantidad,
    d.cantidad * d.precio_unitario AS subtotal
FROM pedido p
JOIN cliente c ON c.id_cliente = p.id_cliente
JOIN detalle d ON d.id_pedido = p.id_pedido
JOIN producto pr ON pr.id_producto = d.id_producto
WHERE p.id_pedido = 1003
ORDER BY pr.nombre;


-- ===============================================================
-- 2. Cada cliente y el nombre de quien lo refirió.
-- LEFT JOIN conserva también a quienes llegaron solos.
-- Esperado: 8 filas.
-- ===============================================================

SELECT
    c.nombre AS cliente,
    r.nombre AS referido_por
FROM cliente c
LEFT JOIN cliente r
    ON r.id_cliente = c.referido_por
ORDER BY c.id_cliente;


-- ===============================================================
-- 3. Productos que nunca se han vendido, ni siquiera en
-- pedidos cancelados.
-- Esperado: 1 fila.
-- ===============================================================

SELECT
    pr.id_producto,
    pr.nombre AS producto
FROM producto pr
WHERE NOT EXISTS (
    SELECT 1
    FROM detalle d
    WHERE d.id_producto = pr.id_producto
)
ORDER BY pr.id_producto;


-- ===============================================================
-- 4. Número de pedidos por cliente, incluidos los cancelados.
-- COUNT(p.id_pedido) permite mostrar 0 para clientes sin pedidos.
-- Esperado: 8 filas.
-- ===============================================================

SELECT
    c.id_cliente,
    c.nombre AS cliente,
    COUNT(p.id_pedido) AS total_pedidos
FROM cliente c
LEFT JOIN pedido p
    ON p.id_cliente = c.id_cliente
GROUP BY c.id_cliente, c.nombre
ORDER BY total_pedidos DESC, c.id_cliente;


-- ===============================================================
-- 5. Total vendido por categoría, excluyendo pedidos cancelados.
-- El subtotal histórico se calcula con precio_unitario.
-- Esperado: 3 filas.
-- ===============================================================

SELECT
    pr.categoria,
    SUM(d.cantidad * d.precio_unitario) AS total_vendido
FROM pedido p
JOIN detalle d ON d.id_pedido = p.id_pedido
JOIN producto pr ON pr.id_producto = d.id_producto
WHERE p.estado <> 'cancelado'
GROUP BY pr.categoria
ORDER BY total_vendido DESC;


-- ===============================================================
-- 6. Meses de 2026 con ventas superiores a $200.000.
-- HAVING filtra los grupos después de calcular sus totales.
-- Esperado: 2 filas.
-- ===============================================================

SELECT
    EXTRACT(MONTH FROM p.fecha)::integer AS mes,
    SUM(d.cantidad * d.precio_unitario) AS total_vendido
FROM pedido p
JOIN detalle d ON d.id_pedido = p.id_pedido
WHERE p.estado <> 'cancelado'
  AND p.fecha >= DATE '2026-01-01'
  AND p.fecha < DATE '2027-01-01'
GROUP BY EXTRACT(MONTH FROM p.fecha)
HAVING SUM(d.cantidad * d.precio_unitario) > 200000
ORDER BY mes;


-- ===============================================================
-- 7. Productos cuyo precio supera el promedio de su categoría.
-- La subconsulta es correlacionada mediante la categoría.
-- Esperado: 4 filas.
-- ===============================================================

SELECT
    pr.id_producto,
    pr.nombre AS producto,
    pr.categoria,
    pr.precio
FROM producto pr
WHERE pr.precio > (
    SELECT AVG(pr2.precio)
    FROM producto pr2
    WHERE pr2.categoria = pr.categoria
)
ORDER BY pr.categoria, pr.precio DESC;


-- ===============================================================
-- 8. Clientes de Cali que compraron al menos un accesorio,
-- excluyendo pedidos cancelados. EXISTS evita duplicados.
-- Esperado: 2 filas.
-- ===============================================================

SELECT
    c.id_cliente,
    c.nombre AS cliente
FROM cliente c
WHERE c.ciudad = 'Cali'
  AND EXISTS (
      SELECT 1
      FROM pedido p
      JOIN detalle d ON d.id_pedido = p.id_pedido
      JOIN producto pr ON pr.id_producto = d.id_producto
      WHERE p.id_cliente = c.id_cliente
        AND p.estado <> 'cancelado'
        AND pr.categoria = 'Accesorio'
  )
ORDER BY c.id_cliente;


-- ===============================================================
-- 9. Clientes que no han referido a nadie.
--
-- La consulta original con NOT IN devuelve 0 filas porque la
-- subconsulta incluye valores NULL de referido_por.
-- En SQL, una comparación con NULL produce UNKNOWN. Por tanto,
-- NOT IN no puede determinar cuáles clientes cumplen la condición.
--
-- Se utiliza NOT EXISTS para comprobar que ningún otro cliente
-- tenga como referido_por el identificador del cliente evaluado.
-- Esperado: 5 filas.
-- ===============================================================

SELECT
    c.id_cliente,
    c.nombre AS cliente
FROM cliente c
WHERE NOT EXISTS (
    SELECT 1
    FROM cliente referido
    WHERE referido.referido_por = c.id_cliente
)
ORDER BY c.id_cliente;


-- ===============================================================
-- 10. Cliente o clientes que más han gastado, sin pedidos
-- cancelados. Se conservan todos los empates mediante MAX.
-- Esperado: 2 filas.
-- ===============================================================

WITH gasto_cliente AS (
    SELECT
        c.id_cliente,
        c.nombre AS cliente,
        SUM(d.cantidad * d.precio_unitario) AS total_gastado
    FROM cliente c
    JOIN pedido p ON p.id_cliente = c.id_cliente
    JOIN detalle d ON d.id_pedido = p.id_pedido
    WHERE p.estado <> 'cancelado'
    GROUP BY c.id_cliente, c.nombre
)
SELECT
    id_cliente,
    cliente,
    total_gastado
FROM gasto_cliente
WHERE total_gastado = (
    SELECT MAX(total_gastado)
    FROM gasto_cliente
)
ORDER BY id_cliente;


-- ===============================================================
-- 11. Clientes que compraron todos los productos de la categoría
-- Grano, excluyendo pedidos cancelados.
--
-- Doble NOT EXISTS: no existe un producto Grano para el cual
-- no exista una compra válida realizada por ese cliente.
-- Esperado: 2 filas.
-- ===============================================================

SELECT
    c.id_cliente,
    c.nombre AS cliente
FROM cliente c
WHERE NOT EXISTS (
    SELECT 1
    FROM producto pr
    WHERE pr.categoria = 'Grano'
      AND NOT EXISTS (
          SELECT 1
          FROM pedido p
          JOIN detalle d ON d.id_pedido = p.id_pedido
          WHERE p.id_cliente = c.id_cliente
            AND p.estado <> 'cancelado'
            AND d.id_producto = pr.id_producto
      )
)
ORDER BY c.id_cliente;
