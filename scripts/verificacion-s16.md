# S16 - Verificación de los reportes de biblioteca

**Base de datos:** `curso`
**Esquema:** `biblioteca`
**Fecha de ejecución:** 9 de noviembre de 2026
**Archivo de consultas:** `scripts/reportes.sql`
**Evidencia:** `evidencias/salida-reportes-s16.txt`

## Criterios generales

- Un libro sin préstamos no aparece en el reporte 1 porque se utiliza `INNER JOIN`.
- El reporte 1 devuelve exactamente 20 libros. Los empates en el último puesto se resuelven alfabéticamente por título.
- El reporte 2 cuenta préstamos con devolución registrada y conserva todos los empates en el máximo.
- Un préstamo se considera moroso cuando su vencimiento es anterior a `CURRENT_DATE` y no tiene devolución registrada.
- Los reportes 3 y 4 excluyen los préstamos devueltos, incluso si la devolución fue tardía.
- Los préstamos que vencen hoy no se consideran morosos.

## Tabla de verificación

| Caso | Resultado esperado | Resultado obtenido | Corrección realizada u observación |
|---|---|---|---|
| 1. Libro que nunca se ha prestado | El libro no aparece si el reporte muestra únicamente libros prestados, siempre que se documente ese comportamiento. | Cumplido. El reporte 1 muestra 20 libros con préstamos. El libro 22, que no tiene préstamos, no aparece. | No fue necesario modificar la consulta. Se documentó el uso de `INNER JOIN` y la exclusión de libros sin préstamos. |
| 2. Dos libros empatados en el último puesto del top 20 | Ambos deben aparecer o debe documentarse un criterio de desempate. | Cumplido. Hay 21 libros con préstamos y varios tienen un préstamo. El reporte devuelve 20 y excluye `Un mundo feliz` (libro 15) por el orden alfabético. | Se documentó el desempate mediante `ORDER BY total_prestamos DESC, l.titulo ASC`. |
| 3. Dos lectores empatados en el primer lugar de libros leídos | Los dos lectores deben aparecer en el reporte 2. | Cumplido. Mariana Gómez Rojas (ID 1) y Santiago Rodríguez Pérez (ID 2) aparecen con 4 libros leídos cada uno. | No fue necesario corregir la consulta. Se conserva el empate mediante la comparación con `MAX(total_libros_leidos)`. |
| 4. Lector con varios préstamos abiertos y ninguna devolución | No debe aparecer como lector con más libros leídos, o debe aparecer con cero si se documenta esa alternativa. | Cumplido. El lector ID 3 tiene 9 préstamos activos y ninguna devolución. No aparece en el reporte 2. | No fue necesario modificar la consulta. Los `INNER JOIN` con devoluciones excluyen a quienes no tienen libros devueltos. |
| 5. Préstamo devuelto después de la fecha de vencimiento | Un préstamo ya devuelto no debe aparecer como moroso en los reportes 3 y 4. | Cumplido. Los préstamos 1003 y 1023 tienen devolución tardía y no aparecen en los reportes de morosidad. | Se verifica la existencia de una devolución mediante `NOT EXISTS`; así se excluyen los préstamos devueltos, independientemente de que la devolución haya sido tardía. |
| 6. Préstamo cuyo vencimiento es hoy | Debe aplicarse el criterio documentado de vencimiento. Con la condición `< CURRENT_DATE`, no se considera moroso hasta el día siguiente. | Cumplido. Los préstamos 1007 y 1021 vencen el 9 de noviembre de 2026 y no aparecen en los reportes 3 y 4. | Se dejó explícito el criterio `fecha_vencimiento < CURRENT_DATE` en ambos reportes. |
| 7. Lector con dos préstamos vencidos | Debe aparecer una sola vez en el reporte 3 y dos veces en el reporte 4. | Cumplido. Los lectores ID 1 y 4 tienen dos préstamos vencidos cada uno. Cada uno aparece una vez en el reporte 3 y dos veces en el reporte 4. | No fue necesario modificar las consultas. El reporte 3 utiliza `EXISTS` y el reporte 4 muestra el detalle individual de cada préstamo. |
| 8. Lector que nunca ha realizado préstamos | No debe provocar errores ni aparecer indebidamente en los reportes de lectores con libros leídos o morosos. | Cumplido. El lector ID 5 no tiene préstamos y no aparece en los reportes 2, 3 ni 4. | No fue necesario modificar las consultas. Los reportes utilizan las relaciones y condiciones correspondientes para incluir únicamente lectores con actividad pertinente. |

## Resumen de resultados obtenidos

| Reporte | Filas obtenidas |
|---|---:|
| 1. Top 20 libros más prestados | 20 |
| 2. Lectores con más libros leídos | 2 |
| 3. Lectores morosos | 3 |
| 4. Detalle de préstamos vencidos | 5 |

**Resultado general:** los ocho casos de prueba fueron satisfactorios. No se identificaron errores en los resultados finales. Se documentaron los criterios de exclusión y desempate y se hizo explícita la condición de vencimiento basada en `CURRENT_DATE`.
