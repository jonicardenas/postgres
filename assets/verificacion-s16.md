# S16 - Verificación de los reportes de biblioteca

**Base de datos:** `curso`
**Esquema:** `biblioteca`
**Fecha de ejecución:** 9 de noviembre de 2026
**Archivo de consultas:** `scripts/reportes.sql`
**Evidencia:** `assets/salida-reportes-s16.txt`

## Criterios generales

- Se utiliza `LEFT JOIN` para contabilizar todo el catálogo (los libros sin préstamos se cuentan con 0 mediante `COUNT(p."PK_id_prestamo")`).
- El reporte 1 conserva los empates en el puesto 20 mediante `FETCH FIRST 20 ROWS WITH TIES` (obteniendo 21 filas).
- El reporte 2 cuenta préstamos con devolución registrada y conserva todos los empates en el máximo.
- Un préstamo se considera moroso cuando su vencimiento es anterior a `CURRENT_DATE` y no tiene devolución registrada.
- Los reportes 3 y 4 excluyen los préstamos devueltos, incluso si la devolución fue tardía.
- Los préstamos que vencen hoy no se consideran morosos.

## Tabla de verificación

| Caso | Resultado esperado | Resultado obtenido | Corrección realizada u observación |
|---|---|---|---|
| 1. Libro que nunca se ha prestado | El libro cuenta con 0 préstamos; no desplaza a los libros con préstamos ni aparece en el top 20 si hay 20 o más con préstamos. | Cumplido. Los libros sin préstamos tienen 0 y quedan fuera del top 20 porque existen 21 libros con al menos 1 préstamo. | Se conserva la solución de S15 con `LEFT JOIN` y `COUNT(p."PK_id_prestamo")`. |
| 2. Dos libros empatados en el último puesto del top 20 | Ambos deben aparecer conservando los empates en el límite. | Cumplido. Hay 16 libros empatados con 1 préstamo (puestos 6 al 21); el reporte devuelve 21 filas e incluye a `Un mundo feliz`. | Se utiliza `FETCH FIRST 20 ROWS WITH TIES` según S15. |
| 3. Dos lectores empatados en el primer lugar de libros leídos | Los dos lectores deben aparecer en el reporte 2. | Cumplido. Mariana Gómez Rojas (ID 1) y Santiago Rodríguez Pérez (ID 2) aparecen con 4 libros leídos cada uno. | Se conserva el empate mediante la comparación con `MAX(total_libros_leidos)`. |
| 4. Lector con varios préstamos abiertos y ninguna devolución | No debe aparecer como lector con más libros leídos, o debe aparecer con cero si se documenta esa alternativa. | Cumplido. El lector ID 3 tiene 9 préstamos activos y ninguna devolución. No aparece en el reporte 2. | El join con devoluciones excluye a quienes no tienen libros devueltos. |
| 5. Préstamo devuelto después de la fecha de vencimiento | Un préstamo ya devuelto no debe aparecer como moroso en los reportes 3 y 4. | Cumplido. Los préstamos 1003 y 1023 tienen devolución tardía y no aparecen en los reportes de morosidad. | Se verifica la existencia de una devolución mediante `NOT EXISTS`; así se excluyen los préstamos devueltos. |
| 6. Préstamo cuyo vencimiento es hoy | Debe aplicarse el criterio documentado de vencimiento. Con la condición `< CURRENT_DATE`, no se considera moroso hasta el día siguiente. | Cumplido. Los préstamos 1007 y 1021 vencen en `CURRENT_DATE` y no aparecen en los reportes 3 y 4. | Se dejó explícito el criterio `fecha_vencimiento < CURRENT_DATE` en ambos reportes. |
| 7. Lector con dos préstamos vencidos | Debe aparecer una sola vez en el reporte 3 y dos veces en el reporte 4. | Cumplido. Los lectores ID 1 y 4 tienen dos préstamos vencidos cada uno. Cada uno aparece una vez en el reporte 3 y dos veces en el reporte 4. | El reporte 3 utiliza `EXISTS` y el reporte 4 muestra el detalle individual de cada préstamo. |
| 8. Lector que nunca ha realizado préstamos | No debe provocar errores ni aparecer indebidamente en los reportes de lectores con libros leídos o morosos. | Cumplido. El lector ID 5 no tiene préstamos y no aparece en los reportes 2, 3 ni 4. | Las condiciones relacionales aíslan limpiamente la actividad de cada usuario. |

## Resumen de resultados obtenidos

| Reporte | Filas obtenidas |
|---|---:|
| 1. Top 20 libros más prestados | 21 |
| 2. Lectores con más libros leídos | 2 |
| 3. Lectores morosos | 3 |
| 4. Detalle de préstamos vencidos | 5 |

**Resultado general:** los ocho casos de prueba fueron satisfactorios. No se identificaron errores en los resultados finales. Se documentaron los criterios de exclusión y desempate y se hizo explícita la condición de vencimiento basada en `CURRENT_DATE`.
