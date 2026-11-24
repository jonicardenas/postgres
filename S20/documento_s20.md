# Normalización de la base de datos — S20 (Hito 3)

## 1. Esquema antes de la normalización

El esquema original de `biblioteca` estaba compuesto por seis tablas principales y una tabla auxiliar para los procesos de carga:

- `rol`: almacena los roles del sistema.
- `usuario`: registra los usuarios y referencia su rol.
- `libro`: almacena la información de cada libro del catálogo.
- `ejemplares`: registra las copias físicas asociadas a cada libro.
- `prestamo`: registra los préstamos realizados por los usuarios.
- `devolucion`: registra las devoluciones asociadas a cada préstamo y ejemplar.
- `rechazo_carga`: tabla auxiliar usada en los esquemas `carga_libros` y `carga_lectores`.

**Claves primarias y restricciones `UNIQUE` originales:**

| Tabla | Clave primaria original | Restricciones `UNIQUE` originales |
|---|---|---|
| `rol` | `PK_id_rol` | `uq_rol_nombre` (`nombre_rol`) |
| `usuario` | `PK_id_usuario` | `uq_usuario_correo` (`correo`), `uq_usuario_documento` (`documento`) |
| `libro` | `PK_id_libro` | `uq_libro_isbn` (`isbn`) |
| `ejemplares` | `PK_id_ejemplar` | *(ninguna)* |
| `prestamo` | `PK_id_prestamo` | *(ninguna)* |
| `devolucion` | `("FK_id_prestamo", "FK_id_ejemplar")` | *(ninguna)* |

**Relaciones entre las tablas principales (antes de la migración):**

```text
rol         1 ─── N usuario
usuario     1 ─── N prestamo
libro       1 ─── N prestamo
libro       1 ─── N ejemplares
prestamo    1 ─── N devolucion  (según la PK compuesta original)
ejemplares  1 ─── N devolucion
```

Aunque la regla del negocio establece que cada préstamo tiene como máximo una devolución, la clave primaria compuesta original de `devolucion` (`"FK_id_prestamo", "FK_id_ejemplar"`) permitía registrar más de una fila para el mismo préstamo con ejemplares diferentes.

---

## 2. Dependencias funcionales y claves candidatas

| Tabla | Claves candidatas | Dependencias funcionales y regla que las justifica |
|---|---|---|
| `rol` | `(PK_id_rol)`, `(nombre_rol)` | • `PK_id_rol → nombre_rol` *(cada rol tiene un ID único)*<br>• `nombre_rol → PK_id_rol` *(el nombre del rol es único y no se repite)* |
| `usuario` | `(PK_id_usuario)`, `(documento)`, `(correo)` | • `PK_id_usuario → FK_id_rol, correo, estado, contrasena, nombres, documento, apellidos, telefono` *(cada usuario tiene un ID único)*<br>• `documento → demás atributos` *(cada documento identifica a una sola persona)*<br>• `correo → demás atributos` *(cada correo pertenece a un solo usuario)* |
| `libro` | `(PK_id_libro)`, `(isbn)` | • `PK_id_libro → titulo, autor, editorial, ejemplares_disponibles, anio_publicacion, categoria, isbn` *(cada libro tiene un ID único)*<br>• `isbn → demás atributos` *(cada ISBN identifica una única edición del catálogo)* |
| `ejemplares` | `(PK_id_ejemplar)` | • `PK_id_ejemplar → FK_id_libro, estado` *(cada copia física pertenece a un único libro y tiene una condición física)* |
| `prestamo` | Original: `(PK_id_prestamo)`<br>Adicional incorporada: `(FK_id_usuario, FK_id_libro, fecha_prestamo)` | • `PK_id_prestamo → FK_id_usuario, FK_id_libro, fecha_prestamo, estado_prestamo, fecha_vencimiento` *(cada préstamo tiene un ID único)*<br>• `(FK_id_usuario, FK_id_libro, fecha_prestamo) → PK_id_prestamo, estado_prestamo, fecha_vencimiento` *(un usuario no puede registrar dos préstamos del mismo libro en la misma fecha)* |
| `devolucion` | Declarada original: `(FK_id_prestamo, FK_id_ejemplar)`<br>Clave candidata real: `(FK_id_prestamo)` | • `FK_id_prestamo → FK_id_ejemplar, estado_devolucion, fecha_devolucion` *(cada préstamo tiene como máximo una devolución, por lo que el préstamo determina el ejemplar devuelto, la fecha y el estado)* |

**Alcance:** `rechazo_carga` (`PK_id_rechazo → archivo, linea, contenido, motivo, fecha_rechazo`) es una tabla auxiliar de los procesos de carga que ya está en FNBC/3FN y no requiere cambios.

---

## 3. Forma normal de cada tabla y problemas encontrados

| Tabla | Forma normal original | Problema encontrado |
|---|---|---|
| `rol` | **FNBC** (y **3FN**) | Ninguno. La clave natural `nombre_rol` está protegida con `UNIQUE` y `NOT NULL`. |
| `usuario` | **FNBC** (y **3FN**) | Ninguno. No tiene dependencias parciales ni transitivas y sus claves naturales (`documento`, `correo`) tienen `UNIQUE`. |
| `libro` | **FNBC** (y **3FN**) | `ejemplares_disponibles` es un dato derivado que presentó descuadres frente a los préstamos abiertos. `editorial` está en `NULL`. |
| `ejemplares` | **FNBC** (y **3FN**) | El estado `'prestado'` es un valor derivado de los préstamos abiertos, no una condición física del ejemplar. |
| `prestamo` | **FNBC** (y **3FN**) | `estado_prestamo` presentó registros desactualizados al pasar la fecha de vencimiento. Faltaba `UNIQUE ("FK_id_usuario", "FK_id_libro", "fecha_prestamo")`. |
| `devolucion` | **1FN** *(incumple **2FN**)* | Dependencia parcial respecto a la PK compuesta `("FK_id_prestamo", "FK_id_ejemplar")`: los atributos no primos `fecha_devolucion` y `estado_devolucion` dependen solo de `FK_id_prestamo`. |

### Consultas de evidencia y resultados

**1. Tabla `devolucion` (dependencia parcial / verificación de una devolución por préstamo):**
```sql
SELECT "FK_id_prestamo", count(*)
FROM biblioteca.devolucion
GROUP BY "FK_id_prestamo"
HAVING count(*) > 1;
```
- **Resultado:** `0 filas` (14 devoluciones para 14 préstamos distintos). Confirma que `FK_id_prestamo` determina toda la fila y debe ser la única clave primaria.

**2. Tabla `prestamo` (verificación de préstamos duplicados por usuario, libro y fecha):**
```sql
SELECT "FK_id_usuario", "FK_id_libro", "fecha_prestamo", count(*)
FROM biblioteca.prestamo
GROUP BY "FK_id_usuario", "FK_id_libro", "fecha_prestamo"
HAVING count(*) > 1;
```
- **Resultado:** `0 filas` entre los 31 préstamos cargados.

**3. Tabla `ejemplares` (estado `'prestado'` frente a préstamos abiertos reales):**
```sql
SELECT (SELECT count(*) FROM biblioteca.ejemplares WHERE "estado" = 'prestado') AS marcados_prestados,
       (SELECT count(*) FROM biblioteca.prestamo p
         WHERE NOT EXISTS (SELECT 1 FROM biblioteca.devolucion d
                            WHERE d."FK_id_prestamo" = p."PK_id_prestamo")) AS prestamos_abiertos;
```
- **Resultado:** `marcados_prestados = 0`, `prestamos_abiertos = 17`. Ningún ejemplar se marcaba como `'prestado'` al registrar préstamos.

**4. Tabla `libro` (descuadre entre `ejemplares_disponibles` guardado y calculado):**
```sql
SELECT l."PK_id_libro", l."titulo", l."ejemplares_disponibles" AS guardado,
       (SELECT count(*) FROM biblioteca.ejemplares e WHERE e."FK_id_libro" = l."PK_id_libro")
     - (SELECT count(*) FROM biblioteca.prestamo p
         WHERE p."FK_id_libro" = l."PK_id_libro"
           AND NOT EXISTS (SELECT 1 FROM biblioteca.devolucion d
                            WHERE d."FK_id_prestamo" = p."PK_id_prestamo")) AS calculado
FROM biblioteca.libro l
WHERE l."ejemplares_disponibles" <>
      (SELECT count(*) FROM biblioteca.ejemplares e WHERE e."FK_id_libro" = l."PK_id_libro")
    - (SELECT count(*) FROM biblioteca.prestamo p
        WHERE p."FK_id_libro" = l."PK_id_libro"
          AND NOT EXISTS (SELECT 1 FROM biblioteca.devolucion d
                           WHERE d."FK_id_prestamo" = p."PK_id_prestamo"));
```
- **Resultado antes de corregir:** 12 libros desfasados en el diagnóstico de S19 (15 al incluir los préstamos de empate; por ejemplo, el libro 1 *"Cien años de soledad"* tenía `guardado = 4`, pero con 4 copias y 2 préstamos abiertos el valor real era `calculado = 2`).

**5. Tabla `prestamo` (descuadre en `estado_prestamo`):**
```sql
SELECT p."PK_id_prestamo", p."fecha_vencimiento", p."estado_prestamo" AS guardado,
       CASE
         WHEN d."FK_id_prestamo" IS NOT NULL THEN 'devuelto'
         WHEN p."fecha_vencimiento" < CURRENT_DATE THEN 'vencido'
         ELSE 'activo'
       END AS calculado
FROM biblioteca.prestamo p
LEFT JOIN biblioteca.devolucion d ON d."FK_id_prestamo" = p."PK_id_prestamo"
WHERE p."estado_prestamo" <> CASE
         WHEN d."FK_id_prestamo" IS NOT NULL THEN 'devuelto'
         WHEN p."fecha_vencimiento" < CURRENT_DATE THEN 'vencido'
         ELSE 'activo'
       END;
```
- **Resultado antes de corregir:** detectó los préstamos abiertos cuya `fecha_vencimiento` ya había pasado pero seguían con `estado_prestamo = 'activo'` (préstamos `1007` y `1021` en S19, más `1012` al correr la migración en la fecha actual).

---

## 4. Cambios aplicados y migración de datos (`scripts/normalizacion.sql`)

La migración se escribió en `scripts/normalizacion.sql` dentro de una transacción (`BEGIN` … `COMMIT`) y los mismos ajustes se dejaron en `init/01_esquema.sql` y `scripts/datos-prueba.sql`:

1. **`devolucion`:** se cambió la clave primaria compuesta por `PRIMARY KEY ("FK_id_prestamo")`, eliminando la dependencia parcial y llevando la tabla a **3FN / FNBC**.
2. **`ejemplares`:** se limpió cualquier estado `'prestado'` a `'disponible'` y se actualizó `ck_ejemplares_estado` a `CHECK ("estado" IN ('disponible', 'danado', 'mantenimiento'))`.
3. **`prestamo`:** se agregó `CONSTRAINT uq_prestamo_usuario_libro_fecha UNIQUE ("FK_id_usuario", "FK_id_libro", "fecha_prestamo")`.
4. **Datos derivados y vistas de verificación:** se actualizaron con `UPDATE` las filas desfasadas de `libro.ejemplares_disponibles` y `prestamo.estado_prestamo`, y se crearon las vistas `v_descuadre_disponibles` y `v_descuadre_estado_prestamo`.

Como todas las tablas excepto `devolucion` ya estaban en 3FN/FNBC y la corrección de `devolucion` consistió en ajustar su clave primaria sin partir la tabla en dos, no hubo descomposición que reconstruir con joins y `EXCEPT`. La verificación se hizo comprobando los conteos antes y después y revisando que ambas vistas de descuadre devuelvan 0 filas:

| Tabla | Conteo antes (semilla / con propios) | Conteo después (semilla / con propios) |
|---|---:|---:|
| `rol` | 1 | 1 |
| `usuario` | 20 / 25 | 20 / 25 |
| `libro` | 32 / 37 | 32 / 37 |
| `ejemplares` | 94 / 114 | 94 / 114 |
| `prestamo` | 31 | 31 |
| `devolucion` | 14 | 14 |

Además, se probó `init/01_esquema.sql` en una base vacía (`prueba_init`) y se corrieron `scripts/datos-prueba.sql` y `scripts/reportes.sql` sobre el esquema actualizado, obteniendo los mismos resultados de S16 (`21` filas en el reporte 1, `2` filas en el reporte 2, `3` filas en el reporte 3 y `5` filas en el reporte 4).

---

## 5. Desnormalizaciones deliberadas

### 5.1. `libro.ejemplares_disponibles`
- **Qué y por qué:** Se conserva la columna `ejemplares_disponibles` en `libro` para evitar recorrer `ejemplares` y `prestamo` en cada búsqueda del catálogo y mantener compatibilidad con `scripts/carga-libros.sql`. En las pruebas de la Parte A sobre el esquema `rendimiento` (5 000 libros, 15 000 ejemplares y 303 750 préstamos) se obtuvieron estos tiempos con `EXPLAIN ANALYZE`:

  | Consulta | Sin índices | Con índices (A2) | Desnormalizada (A3 o A4) |
  |---|---|---|---|
  | Catálogo (`Libro 12%`) | 23.88 ms *(26.13 / 22.28 / 23.88 ms)* | 2.37 ms *(2.42 / 2.37 / 1.95 ms)* | **0.38 ms** *(0.38 / 0.38 / 0.35 ms)* |
  | Top 20 más prestados | 196.37 ms *(196.37 / 210.20 / 188.48 ms)* | *(no aplica)* | **0.007 ms** *(0.014 / 0.007 / 0.005 ms)* |

- **Cómo se mantiene consistente:** Se actualiza en la misma transacción en `scripts/datos-prueba.sql` y `scripts/normalizacion.sql`. Su actualización automática mediante un **trigger** en cada préstamo y devolución queda anotada como pendiente para el **Hito 4 (M6)**.
- **Consulta de verificación (`v_descuadre_disponibles`):**
  ```sql
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
  ```

### 5.2. `prestamo.estado_prestamo`
- **Qué y por qué:** Se conserva por compatibilidad con `scripts/datos-prueba.sql`.
- **Cómo se mantiene y verificación (`v_descuadre_estado_prestamo`):** Se actualiza al registrar préstamos/devoluciones (pendiente por trigger en el Hito 4). Como un trigger no se ejecuta solo cuando pasa la fecha de vencimiento, los reportes de mora de `scripts/reportes.sql` consultan directamente `fecha_vencimiento < CURRENT_DATE` y el estado guardado se verifica con la vista:
  ```sql
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
  ```

### 5.3. Datos históricos que se conservan por estar en 3FN
- **`prestamo.fecha_vencimiento`:** Aunque el plazo por defecto sea de 14 días, la biblioteca puede cambiar el plazo o dar plazos distintos (en `datos-prueba.sql` hay préstamos con 10, 14 y 29 días). Por tanto, es un dato histórico que depende de `PK_id_prestamo` y está en **3FN**.
- **`devolucion.estado_devolucion`:** Se conserva por compatibilidad con `scripts/datos-prueba.sql`; el valor `'danado'` registra la condición física en la entrega, mientras que `'a_tiempo'` y `'tardia'` coinciden con comparar `fecha_devolucion > fecha_vencimiento`.

---

## 6. Esquema después de la normalización

Después de los cambios, **todas las seis tablas del esquema `biblioteca` quedan en 3FN y también en FNBC** (ninguna tabla queda solo en 3FN sin cumplir FNBC, porque en todas las dependencias funcionales cada determinante es superclave de su tabla):

- **`rol`** (`"PK_id_rol"` PK, `"nombre_rol"` UNIQUE NOT NULL) — **FNBC**
- **`usuario`** (`"PK_id_usuario"` PK, `"FK_id_rol"` FK → `rol`, `"correo"` UNIQUE NOT NULL, `"documento"` UNIQUE NOT NULL, `"estado"` CHECK IN (`'activo'`, `'inactivo'`, `'suspendido'`), `"contrasena"` NOT NULL, `"nombres"` NOT NULL, `"apellidos"` NOT NULL, `"telefono"`) — **FNBC**
- **`libro`** (`"PK_id_libro"` PK, `"isbn"` UNIQUE NOT NULL, `"titulo"` NOT NULL, `"autor"` NOT NULL, `"editorial"`, `"ejemplares_disponibles"` NOT NULL CHECK `>= 0` *[desnormalizado]*, `"anio_publicacion"` CHECK `BETWEEN 1400 AND 2100`, `"categoria"`) — **FNBC**
- **`ejemplares`** (`"PK_id_ejemplar"` PK, `"FK_id_libro"` FK → `libro`, `"estado"` NOT NULL CHECK IN (`'disponible'`, `'danado'`, `'mantenimiento'`)) — **FNBC**
- **`prestamo`** (`"PK_id_prestamo"` PK, `"FK_id_usuario"` FK → `usuario`, `"FK_id_libro"` FK → `libro`, `"fecha_prestamo"` NOT NULL, `"fecha_vencimiento"` NOT NULL CHECK `>= "fecha_prestamo"`, `"estado_prestamo"` NOT NULL CHECK IN (`'activo'`, `'devuelto'`, `'vencido'`) *[desnormalizado]*, UNIQUE `("FK_id_usuario", "FK_id_libro", "fecha_prestamo")`) — **FNBC**
- **`devolucion`** (`"FK_id_prestamo"` PK y FK → `prestamo`, `"FK_id_ejemplar"` FK → `ejemplares`, `"estado_devolucion"` NOT NULL CHECK IN (`'a_tiempo'`, `'tardia'`, `'danado'`), `"fecha_devolucion"` NOT NULL) — **FNBC**
- **Vistas de verificación:** `v_descuadre_disponibles` y `v_descuadre_estado_prestamo`.

```text
rol         1 ─── N usuario
usuario     1 ─── N prestamo
libro       1 ─── N prestamo
libro       1 ─── N ejemplares
prestamo    1 ─── 0..1 devolucion
ejemplares  1 ─── N devolucion
```
