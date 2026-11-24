# Documento de normalizacion - Hito 3

**Proyecto:** Biblioteca
**Esquema analizado:** `biblioteca`
**Fuente:** `init/01_esquema.sql`, análisis de S19 y taller S20

## 1. Esquema antes

El esquema contiene las siguientes entidades principales:

- `rol`: identifica los roles del sistema.
- `usuario`: identifica lectores y administradores; se relaciona con `rol`.
- `libro`: representa el título o edición del catálogo.
- `ejemplares`: representa las copias físicas de cada libro.
- `prestamo`: registra el usuario, el libro, las fechas y el estado del préstamo.
- `devolucion`: registra el préstamo, el ejemplar entregado, su estado y la fecha.

Claves y relaciones principales:

```text
rol 1 --> N usuario
libro 1 --> N ejemplares
usuario 1 --> N prestamo
libro 1 --> N prestamo
prestamo 1 --> 0..1 devolucion
ejemplares 1 --> N devolucion
```

## 2. Dependencias funcionales y claves candidatas

| Tabla | Clave candidata | Dependencias funcionales y regla |
|---|---|---|
| `rol` | `PK_id_rol`, `nombre_rol` | El identificador determina el nombre y el nombre no se repite, porque es único. |
| `usuario` | `PK_id_usuario`, `documento`, `correo` | Cada identificador, documento o correo identifica un usuario y determina sus demás datos. |
| `libro` | `PK_id_libro`, `isbn` | Cada identificador o ISBN identifica una edición y determina título, autor, categoría y demás datos del libro. |
| `ejemplares` | `PK_id_ejemplar` | Cada copia física determina su libro y su condición. |
| `prestamo` | `PK_id_prestamo`; candidata adicional `(FK_id_usuario, FK_id_libro, fecha_prestamo)` como regla propuesta | El identificador determina usuario, libro, fechas y estado. Esta combinación debería ser única si no se permiten dos préstamos idénticos el mismo día. |
| `devolucion` | `FK_id_prestamo` como clave propuesta | Un préstamo tiene como máximo una devolución; por tanto, el préstamo determina el ejemplar devuelto, la fecha y el estado. |

## 3. Forma normal y problemas encontrados

Las tablas `rol`, `usuario`, `libro`, `ejemplares` y `prestamo` están en 3FN y cumplen FNBC con las reglas y claves actuales. No se encontró una dependencia transitiva o parcial que exija descomponer estas tablas.

Sin embargo, existen problemas que deben corregirse:

1. `libro.ejemplares_disponibles` es un dato derivado. Puede calcularse con las copias físicas y los préstamos abiertos.
2. `ejemplares.estado = 'prestado'` puede ser derivado de los préstamos y devoluciones. Los estados físicos son datos reales; el préstamo activo no es una propiedad permanente de la copia.
3. `prestamo.estado_prestamo` es derivable de la devolución y de `fecha_vencimiento`.
4. `prestamo.FK_id_libro` no identifica qué ejemplar físico fue entregado. Esa información solo aparece en `devolucion`; por ello, mientras el préstamo está abierto no puede determinarse exactamente cuál copia está ocupada.
5. La clave primaria compuesta de `devolucion` permite registrar varias devoluciones del mismo préstamo. Si la regla es una devolución por préstamo, `FK_id_prestamo` debe ser clave primaria.
6. `prestamo` no tiene una restricción que impida duplicar el mismo préstamo de un usuario por el mismo libro en la misma fecha.

Consultas de evidencia:

```sql
-- Disponibilidad almacenada versus disponibilidad calculada
SELECT l."PK_id_libro",
       l."ejemplares_disponibles" AS guardado,
       count(DISTINCT e."PK_id_ejemplar") -
       count(DISTINCT p."PK_id_prestamo") FILTER (
           WHERE NOT EXISTS (
               SELECT 1
               FROM biblioteca.devolucion d
               WHERE d."FK_id_prestamo" = p."PK_id_prestamo"
           )
       ) AS calculado
FROM biblioteca.libro l
LEFT JOIN biblioteca.ejemplares e
       ON e."FK_id_libro" = l."PK_id_libro"
LEFT JOIN biblioteca.prestamo p
       ON p."FK_id_libro" = l."PK_id_libro"
GROUP BY l."PK_id_libro", l."ejemplares_disponibles"
HAVING l."ejemplares_disponibles" <>
       count(DISTINCT e."PK_id_ejemplar") -
       count(DISTINCT p."PK_id_prestamo") FILTER (
           WHERE NOT EXISTS (
               SELECT 1
               FROM biblioteca.devolucion d
               WHERE d."FK_id_prestamo" = p."PK_id_prestamo"
           )
       );
```

```sql
-- Estado calculado de préstamos y estado almacenado
SELECT p."PK_id_prestamo",
       p."estado_prestamo" AS guardado,
       CASE
           WHEN d."FK_id_prestamo" IS NOT NULL THEN 'devuelto'
           WHEN p."fecha_vencimiento" < CURRENT_DATE THEN 'vencido'
           ELSE 'activo'
       END AS calculado
FROM biblioteca.prestamo p
LEFT JOIN biblioteca.devolucion d
       ON d."FK_id_prestamo" = p."PK_id_prestamo"
WHERE p."estado_prestamo" <> CASE
          WHEN d."FK_id_prestamo" IS NOT NULL THEN 'devuelto'
          WHEN p."fecha_vencimiento" < CURRENT_DATE THEN 'vencido'
          ELSE 'activo'
      END;
```

```sql
-- Más de una devolución por préstamo
SELECT "FK_id_prestamo", count(*)
FROM biblioteca.devolucion
GROUP BY "FK_id_prestamo"
HAVING count(*) > 1;

-- Posibles préstamos duplicados según la regla propuesta
SELECT "FK_id_usuario", "FK_id_libro", "fecha_prestamo", count(*)
FROM biblioteca.prestamo
GROUP BY "FK_id_usuario", "FK_id_libro", "fecha_prestamo"
HAVING count(*) > 1;
```

Los resultados esperados son cero filas en ambas consultas si ya se corrigieron las restricciones y no existen duplicados.

## 4. Cambios y migración

No se realizaron cambios de normalización destructivos en el esquema inicial, pero el esquema corregido debería incluir:

```sql
ALTER TABLE biblioteca.devolucion
    DROP CONSTRAINT pk_devolucion;

ALTER TABLE biblioteca.devolucion
    ADD CONSTRAINT pk_devolucion PRIMARY KEY ("FK_id_prestamo");
```

La migración debe ejecutarse dentro de `BEGIN` y `COMMIT`, después de comprobar que no existan dos devoluciones para el mismo préstamo. También se puede agregar:

```sql
ALTER TABLE biblioteca.prestamo
    ADD CONSTRAINT uq_prestamo_usuario_libro_fecha
    UNIQUE ("FK_id_usuario", "FK_id_libro", "fecha_prestamo");
```

La restricción debe agregarse solo después de verificar que no hay filas duplicadas por esa combinación.

Antes y después deben comprobarse conteos y reconstrucción con `EXCEPT`, según la receta de S19. `postgres/scripts/normalizacion.sql` se crea si la migración se aplica; si no hay cambios en el esquema, se justifica su ausencia.

## 5. Desnormalizaciones deliberadas

**`libro.ejemplares_disponibles`.** Se considera una desnormalización si se conserva. El cálculo normal requiere recorrer ejemplares y préstamos, pero hay mecanismos que podrían mantenerlo:

- preferido para el proyecto: trigger en préstamos y devoluciones;
- alternativa: aplicación que actualice ambas tablas en la misma transacción;
- vista o consulta de verificación que compare el dato guardado con el cálculo real.

No se debe mantener sin control, porque el taller mostró que una carga o devolución olvidada puede desfasar la copia.

**`prestamo.estado_prestamo`.** Es un dato derivado y puede eliminarse o calcularse en una vista. Si se conserva por compatibilidad con las cargas y reportes, su mantenimiento requiere recalcularlo al crear o devolver un préstamo y revisar los vencimientos por fecha. Un trigger de eventos no cambia automáticamente el estado cuando pasa el vencimiento; por ello sigue siendo necesaria una verificación basada en `CURRENT_DATE`.

**`ejemplares.estado`.** Se recomienda conservar únicamente estados físicos reales (`disponible`, `prestado`, `danado`, `mantenimiento`) o, de forma más normalizada, eliminar `prestado` y determinarlo mediante préstamos abiertos. El estado `'prestado'` puede desnormalizarse si se sincroniza automáticamente al prestar y devolver.

**`devolucion.estado_devolucion`.** Los estados `'a_tiempo'` y `'tardia'` pueden calcularse comparando `fecha_devolucion` con `fecha_vencimiento`. Si el negocio necesita conservar una clasificación histórica y no cambiarla por modificaciones posteriores, ese estado sí puede considerarse histórico y se conserva.

## 6. Evidencia de S20 y esquema después

En el esquema grande de prueba S20, la consulta normalizada tardó entre 35 y 61 ms sin índices. Con los índices:

- `ejemplar_isbn_idx`;
- `prestamo_abierto_idx` como índice parcial;

el tiempo típico bajó a entre 3.9 y 4.8 ms. El plan cambió de `Seq Scan` sobre 303 750 préstamos con 300 000 filas descartadas a `Index Scan` sobre préstamos abiertos.

Al desnormalizar `disponibles`, la consulta pasó a entre 0.8 y 1.5 ms. También se verificó que un préstamo olvidado produjo un descuadre: el dato guardado quedó en 3 y el calculado en 2.

El reporte top 20 como vista materializada tardó alrededor de 0.01–0.03 ms. La vista quedó atrasada hasta ejecutarse `REFRESH MATERIALIZED VIEW`; por ello conviene refrescarla una vez al día o en el momento del reporte, no después de cada préstamo.

Como conclusión del Hito 3, el proyecto conserva su estructura normalizada, corrige la clave de `devolucion`, evita duplicados mediante restricciones y decide qué datos derivados conserva únicamente con mecanismos de consistencia y consultas de verificación.
