# S19 – Parte B: Análisis de normalización del esquema Biblioteca

## 1. Objetivo

Analizar la estructura del esquema `biblioteca` definido en `init/01_esquema.sql` mediante la identificación de claves candidatas, dependencias funcionales y formas normales, así como detectar datos derivados, redundancias e inconsistencias, sustentando el diagnóstico con consultas ejecutadas en PostgreSQL.

El análisis se realiza sobre las seis tablas del esquema `biblioteca`:

- `rol`
- `usuario`
- `libro`
- `ejemplares`
- `prestamo`
- `devolucion`

Tal como indica la guía de S19, **no se realizan todavía modificaciones estructurales ni migraciones sobre `init/01_esquema.sql`**, ya que la migración y la decisión de qué datos derivados conservar o desnormalizar corresponden a S20 (Hito 3).

---

## 2. Tabla general de diagnóstico (Parte B)

| Tabla | Claves candidatas | Dependencias (con su regla) | Forma normal más alta | Problema encontrado | Evidencia (consulta) | Cambio propuesto |
|---|---|---|---|---|---|---|
| **`rol`** | `(PK_id_rol)`<br>`(nombre_rol)` | • `PK_id_rol → nombre_rol` *(cada rol tiene un ID único)*<br>• `nombre_rol → PK_id_rol` *(el nombre del rol no se repite; tiene `UNIQUE`)* | **FNBC** (y **3FN**) | **Ninguno.** No hay redundancia y la clave natural `nombre_rol` está protegida con `UNIQUE` y `NOT NULL`. | `SELECT "nombre_rol", count(*) FROM biblioteca.rol GROUP BY "nombre_rol" HAVING count(*) > 1;` *(0 filas; 1 rol registrado: `'lector'`)* | **Ninguno.** Se conserva igual: `rol(PK_id_rol PK, nombre_rol UNIQUE NOT NULL)`. |
| **`usuario`** | `(PK_id_usuario)`<br>`(documento)`<br>`(correo)` | • `PK_id_usuario → FK_id_rol, correo, estado, contrasena, nombres, documento, apellidos, telefono` *(cada usuario tiene un ID único)*<br>• `documento → demás atributos` *(cada documento identifica a un solo usuario; tiene `UNIQUE`)*<br>• `correo → demás atributos` *(cada correo pertenece a un solo usuario; tiene `UNIQUE`)* | **FNBC** (y **3FN**) | **Ninguno de normalización.** Las claves naturales (`documento` y `correo`) tienen `UNIQUE` y el rol está separado en la tabla `rol` mediante `FK_id_rol`. | `SELECT count(*), count(DISTINCT "documento"), count(DISTINCT lower("correo")) FROM biblioteca.usuario;` *(25 usuarios, 25 documentos y 25 correos distintos)* | **Ninguno estructural.** Se conserva la relación entre `usuario` y `rol`. |
| **`libro`** | `(PK_id_libro)`<br>`(isbn)` | • `PK_id_libro → titulo, autor, editorial, ejemplares_disponibles, anio_publicacion, categoria, isbn` *(cada libro tiene un ID único)*<br>• `isbn → demás atributos` *(cada ISBN identifica una única edición del catálogo; tiene `UNIQUE`)* | **FNBC** (y **3FN**) | **1. Dato derivado (`ejemplares_disponibles`):** se puede calcular restando a las copias de `ejemplares` los préstamos abiertos en `prestamo`; quedó desactualizado en 12 libros.<br>**2. Columna vacía (`editorial`):** está en `NULL` en todos los registros.<br>**3. Texto repetido (`autor`, `categoria`):** se repiten entre libros, aunque sin violar 3FN. | • Comparar `libro."ejemplares_disponibles"` con `count(ejemplares) - préstamos abiertos` devuelve **12 libros desfasados** (ej. libro 1: guardado `4`, real `2`).<br>• `SELECT count("editorial") FROM biblioteca.libro;` *(0 con editorial)*<br>• `SELECT "autor", count(*) FROM biblioteca.libro GROUP BY "autor" HAVING count(*) > 1;` *(García Márquez: 4, Borges: 3)* | **1.** Calcular `ejemplares_disponibles` mediante una vista (`VIEW`) que cruce `ejemplares` y `prestamo` (+ `devolucion`), o mantenerlo con trigger en S20.<br>**2.** Quitar `editorial` (o poblarla si se usa).<br>**3.** Mantener `autor` y `categoria` (o llevarlos a tablas de referencia en S20 si se busca evitar errores de digitación). |
| **`ejemplares`** | `(PK_id_ejemplar)` | • `PK_id_ejemplar → FK_id_libro, estado` *(cada ejemplar físico numerado pertenece a un único libro y tiene un estado)* | **FNBC** (y **3FN**) | **Está en 3FN/FNBC, pero `'prestado'` en `estado` es un dato derivado:** saber si una copia está prestada depende de los préstamos abiertos; hay 17 préstamos sin devolución y todos los ejemplares siguen en `'disponible'`. | `SELECT "estado", count(*) FROM biblioteca.ejemplares GROUP BY "estado";` *(todos en `'disponible'`, 0 en `'prestado'`, pese a existir 17 préstamos abiertos)* | **Conservar la tabla en 3FN/FNBC**, usando `estado` solo para la condición física (`'disponible'`, `'danado'`, `'mantenimiento'`) y calculando cuántos están prestados con `prestamo` y `devolucion`. |
| **`prestamo`** | `(PK_id_prestamo)` | • `PK_id_prestamo → FK_id_usuario, FK_id_libro, fecha_prestamo, estado_prestamo, fecha_vencimiento` *(cada préstamo tiene un ID único que determina el usuario, el libro, las fechas y el estado)* | **FNBC** (y **3FN**) | **1. Dato derivado (`estado_prestamo`):** los préstamos `1007` y `1021` vencieron el `2026-11-09`, no tienen devolución y siguen diciendo `'activo'`.<br>**2. Clave sustituta sin `UNIQUE` natural:** falta una restricción que impida duplicar por error el mismo préstamo en la misma fecha. | Consulta que compara `estado_prestamo` con `devolucion` y `fecha_vencimiento < CURRENT_DATE`: detecta los préstamos **1007 y 1021** con estado `'activo'` pero vencidos el `2026-11-09`. | **1.** Calcular el estado en una vista (`devuelto` si existe en `devolucion`, `vencido` si `fecha_vencimiento < CURRENT_DATE`, `activo` en caso contrario) o actualizarlo con trigger en S20.<br>**2.** Evaluar `UNIQUE (FK_id_usuario, FK_id_libro, fecha_prestamo)`. |
| **`devolucion`** | **PK declarada:** `(FK_id_prestamo, FK_id_ejemplar)`<br>**Clave real:** `(FK_id_prestamo)` | • `FK_id_prestamo → FK_id_ejemplar, estado_devolucion, fecha_devolucion` *(cada préstamo corresponde a un solo libro/ejemplar y tiene a lo sumo una devolución)* | **1FN** *(incumple **2FN** respecto a la PK compuesta declarada)* | **1. Dependencia parcial respecto a la PK compuesta `(FK_id_prestamo, FK_id_ejemplar)`:** como un préstamo se devuelve una sola vez, `FK_id_prestamo` determina por sí solo `fecha_devolucion`, `estado_devolucion` y `FK_id_ejemplar`.<br>**2. Dato derivado en `estado_devolucion`:** `'a_tiempo'` y `'tardia'` se calculan comparando `fecha_devolucion > fecha_vencimiento`. | • `SELECT "FK_id_prestamo", count(*) FROM biblioteca.devolucion GROUP BY "FK_id_prestamo" HAVING count(*) > 1;` *(0 filas: 14 devoluciones para 14 préstamos distintos)*<br>• En las 14 filas, comparar `fecha_devolucion > fecha_vencimiento` coincide con las 12 `'a_tiempo'` y las 2 `'tardia'` (`1003` y `1023`). | **1.** Dejar como PK únicamente `(FK_id_prestamo)` para que quede en **3FN / FNBC**: `devolucion(FK_id_prestamo PK/FK → prestamo, FK_id_ejemplar FK → ejemplares, fecha_devolucion, estado_devolucion)`.<br>**2.** Evaluar calcular `'a_tiempo'`/`'tardia'` en una vista. |

---

## 3. Análisis detallado por tabla y consultas de evidencia

### 3.1. Tabla `rol`

- **Atributos:** `PK_id_rol`, `nombre_rol`.
- **Claves candidatas:** `(PK_id_rol)` y `(nombre_rol)` (por `uq_rol_nombre` y `NOT NULL`).
- **Dependencias funcionales y regla:**
  - `PK_id_rol → nombre_rol` y `nombre_rol → PK_id_rol` *(cada rol tiene un identificador propio y un nombre único que no puede repetirse)*.
- **Forma normal más alta:** **FNBC / 3FN**.
- **Problema encontrado:** ninguno.
- **Evidencia (SQL):**
  ```sql
  SELECT "PK_id_rol", "nombre_rol" FROM biblioteca.rol;
  SELECT "nombre_rol", count(*) FROM biblioteca.rol GROUP BY "nombre_rol" HAVING count(*) > 1;
  -- Resultado: 1 fila ('lector') y 0 duplicados.
  ```
- **Cambio propuesto:** conservar la tabla sin cambios.

---

### 3.2. Tabla `usuario`

- **Atributos:** `PK_id_usuario`, `FK_id_rol`, `correo`, `estado`, `contrasena`, `nombres`, `documento`, `apellidos`, `telefono`.
- **Claves candidatas:** `(PK_id_usuario)`, `(correo)` (`uq_usuario_correo`) y `(documento)` (`uq_usuario_documento`).
- **Dependencias funcionales y regla:**
  - `PK_id_usuario → FK_id_rol, correo, estado, contrasena, nombres, documento, apellidos, telefono` *(cada usuario tiene un identificador único)*.
  - `documento → PK_id_usuario, FK_id_rol, correo, estado, contrasena, nombres, apellidos, telefono` *(cada documento identifica a una única persona)*.
  - `correo → PK_id_usuario, FK_id_rol, documento, estado, contrasena, nombres, apellidos, telefono` *(cada correo pertenece a un solo usuario)*.
- **Forma normal más alta:** **FNBC / 3FN**.
- **Problema encontrado:** no se evidencia violación de normalización. La información del rol está separada en la tabla `rol` mediante `FK_id_rol`, evitando repetir `nombre_rol` en cada fila de `usuario`.
- **Evidencia (SQL):**
  ```sql
  SELECT count(*) AS total_usuarios,
         count(DISTINCT "documento") AS documentos_distintos,
         count(DISTINCT lower("correo")) AS correos_distintos
  FROM biblioteca.usuario;
  -- Resultado: 25 usuarios (20 semilla + 5 propios), sin duplicados en documento ni correo.
  ```
- **Cambio propuesto:** conservar la estructura actual en 3FN/FNBC.

---

### 3.3. Tabla `libro` y verificación de `ejemplares_disponibles` con `ejemplares` y `prestamo`

- **Atributos:** `PK_id_libro`, `titulo`, `autor`, `editorial`, `ejemplares_disponibles`, `anio_publicacion`, `categoria`, `isbn`.
- **Claves candidatas:** `(PK_id_libro)` e `(isbn)` (`uq_libro_isbn`).
- **Dependencias funcionales y regla:**
  - `PK_id_libro → titulo, autor, editorial, ejemplares_disponibles, anio_publicacion, categoria, isbn` *(cada libro tiene un identificador interno único)*.
  - `isbn → PK_id_libro, titulo, autor, editorial, ejemplares_disponibles, anio_publicacion, categoria` *(cada ISBN identifica una única edición del catálogo y no puede repetirse)*.
- **Forma normal más alta:** **FNBC / 3FN** (todos sus determinantes son claves candidatas y no existen otros atributos del autor o de la categoría que produzcan una dependencia transitiva).
- **Problemas identificados:**
  1. **Dato derivado redundante (`ejemplares_disponibles`):** en `scripts/carga-libros.sql`, al insertar cada libro se crean sus copias físicas en la tabla `ejemplares` (`generate_series(1, s.ejemplares::INTEGER)`). Por tanto, `ejemplares_disponibles` es un dato derivado que equivale al total de copias del libro en `ejemplares` menos los préstamos abiertos de ese libro en `prestamo` (sin registro en `devolucion`). Al insertar los préstamos de `scripts/datos-prueba.sql`, la columna `libro.ejemplares_disponibles` no se actualizó y quedó con valores falsos en **12 libros**.
  2. **Atributo siempre nulo (`editorial`):** está en `NULL` en todos los libros cargados porque los CSV no incluyen esa columna.
  3. **Valores de texto repetidos (`autor` y `categoria`):** `Gabriel García Márquez` y `Jorge Luis Borges` se repiten en varios libros, igual que las 9 categorías (`Novela`, `Ciencia Ficción`, etc.). Esto no viola 3FN por sí solo, pero podría separarse en catálogos si se busca evitar diferencias de digitación.
- **Evidencia (SQL):**
  ```sql
  -- 1. Editorial siempre en NULL y repetición de autores/categorías:
  SELECT count(*) AS total_libros,
         count("editorial") AS con_editorial,
         count(DISTINCT "autor") AS autores_distintos,
         count(DISTINCT "categoria") AS categorias_distintas
  FROM biblioteca.libro;

  -- 2. Demostración de que ejemplares_disponibles es derivado y contradice a (ejemplares - préstamos abiertos):
  SELECT
      l."PK_id_libro",
      l."titulo",
      l."ejemplares_disponibles" AS guardado_en_libro,
      COUNT(e."PK_id_ejemplar") AS copias_en_ejemplares,
      (
          SELECT COUNT(*)
          FROM biblioteca.prestamo p
          WHERE p."FK_id_libro" = l."PK_id_libro"
            AND NOT EXISTS (
                SELECT 1
                FROM biblioteca.devolucion d
                WHERE d."FK_id_prestamo" = p."PK_id_prestamo"
            )
      ) AS prestamos_abiertos,
      COUNT(e."PK_id_ejemplar") - (
          SELECT COUNT(*)
          FROM biblioteca.prestamo p
          WHERE p."FK_id_libro" = l."PK_id_libro"
            AND NOT EXISTS (
                SELECT 1
                FROM biblioteca.devolucion d
                WHERE d."FK_id_prestamo" = p."PK_id_prestamo"
            )
      ) AS disponibles_reales
  FROM biblioteca.libro l
  LEFT JOIN biblioteca.ejemplares e
      ON e."FK_id_libro" = l."PK_id_libro"
  GROUP BY l."PK_id_libro", l."titulo", l."ejemplares_disponibles"
  HAVING l."ejemplares_disponibles" <> (
      COUNT(e."PK_id_ejemplar") - (
          SELECT COUNT(*)
          FROM biblioteca.prestamo p
          WHERE p."FK_id_libro" = l."PK_id_libro"
            AND NOT EXISTS (
                SELECT 1
                FROM biblioteca.devolucion d
                WHERE d."FK_id_prestamo" = p."PK_id_prestamo"
            )
      )
  )
  ORDER BY l."PK_id_libro";
  -- Resultado: 12 libros presentan diferencia (ej. libro 1 "Cien años de soledad":
  -- guardado_en_libro = 4, copias_en_ejemplares = 4, prestamos_abiertos = 2 -> disponibles_reales = 2).
  ```
- **Cambio propuesto:**
  - Si en S20 se elimina el dato derivado `ejemplares_disponibles` de `libro`, **sí se cumple** el cálculo exacto usando las tablas `ejemplares` y `prestamo` (con `devolucion`) mediante una vista (`CREATE VIEW`), o bien se conserva la columna en `libro` actualizándola con un trigger en cada préstamo y devolución.
  - Eliminar `editorial` si no hace parte del alcance de los datos, o poblarla.

---

### 3.4. Tabla `ejemplares`

- **Atributos:** `PK_id_ejemplar`, `FK_id_libro`, `estado`.
- **Clave candidata:** `(PK_id_ejemplar)`.
- **Dependencia funcional y regla:**
  - `PK_id_ejemplar → FK_id_libro, estado` *(cada copia física tiene un identificador único, pertenece a un único libro del catálogo y tiene un estado)*.
- **Forma normal más alta:** **FNBC / 3FN**.
- **Problema identificado:**
  - Aunque la tabla está en 3FN/FNBC, el valor `'prestado'` dentro del dominio de `estado` (`'disponible'`, `'prestado'`, `'danado'`, `'mantenimiento'`) es un **dato derivado** de los préstamos abiertos. Actualmente existen 17 préstamos sin devolución en `prestamo`, pero el 100% de las filas de `ejemplares` siguen con `estado = 'disponible'`.
- **Evidencia (SQL):**
  ```sql
  SELECT
      (SELECT count(*) FROM biblioteca.ejemplares WHERE "estado" = 'prestado') AS ejemplares_marcados_prestados,
      (SELECT count(*) FROM biblioteca.prestamo p
       WHERE NOT EXISTS (
           SELECT 1 FROM biblioteca.devolucion d
           WHERE d."FK_id_prestamo" = p."PK_id_prestamo"
       )) AS prestamos_abiertos_reales;
  -- Resultado: ejemplares_marcados_prestados = 0, prestamos_abiertos_reales = 17.
  ```
- **Cambio propuesto:** conservar la tabla `ejemplares` en 3FN/FNBC, reservando `estado` para la condición física de la copia (`'disponible'`, `'danado'`, `'mantenimiento'`) y determinando si está prestada a partir de `prestamo` y `devolucion` (o sincronizándola con un trigger en S20).

---

### 3.5. Tabla `prestamo`

- **Atributos:** `PK_id_prestamo`, `FK_id_usuario`, `FK_id_libro`, `fecha_prestamo`, `estado_prestamo`, `fecha_vencimiento`.
- **Clave candidata:** `(PK_id_prestamo)`.
- **Dependencia funcional y regla:**
  - `PK_id_prestamo → FK_id_usuario, FK_id_libro, fecha_prestamo, estado_prestamo, fecha_vencimiento` *(cada préstamo tiene un identificador único que determina el usuario, el libro, las fechas y el estado correspondiente)*.
- **Forma normal más alta:** **FNBC / 3FN** (no copia datos del lector ni del libro).
- **Problemas identificados:**
  1. **Dato derivado desactualizado (`estado_prestamo`):** al consultar los 31 préstamos se encontraron dos registros que siguen almacenados como `'activo'` aunque su fecha de vencimiento ya pasó (`2026-11-09`) y no tienen devolución asociada:
     - **Préstamo 1007:** vencimiento el `2026-11-09`, estado guardado `'activo'`, estado real `'vencido'`.
     - **Préstamo 1021:** vencimiento el `2026-11-09`, estado guardado `'activo'`, estado real `'vencido'`.
  2. **Clave sustituta sin `UNIQUE` sobre la clave natural:** `PK_id_prestamo` no impide registrar por error dos veces el mismo préstamo (`FK_id_usuario, FK_id_libro, fecha_prestamo`).
- **Evidencia (SQL):**
  ```sql
  SELECT
      p."PK_id_prestamo",
      p."fecha_prestamo",
      p."fecha_vencimiento",
      p."estado_prestamo" AS estado_guardado,
      CASE
          WHEN d."FK_id_prestamo" IS NOT NULL THEN 'devuelto'
          WHEN p."fecha_vencimiento" < CURRENT_DATE THEN 'vencido'
          ELSE 'activo'
      END AS estado_calculado
  FROM biblioteca.prestamo p
  LEFT JOIN biblioteca.devolucion d
      ON d."FK_id_prestamo" = p."PK_id_prestamo"
  WHERE p."estado_prestamo" <> CASE
      WHEN d."FK_id_prestamo" IS NOT NULL THEN 'devuelto'
      WHEN p."fecha_vencimiento" < CURRENT_DATE THEN 'vencido'
      ELSE 'activo'
  END;
  -- Resultado: préstamos 1007 y 1021 (estado_guardado = 'activo', estado_calculado = 'vencido').
  ```
- **Cambio propuesto:**
  - Calcular `estado_prestamo` en una vista (`devuelto` si existe en `devolucion`, `vencido` si no existe devolución y `fecha_vencimiento < CURRENT_DATE`, `activo` en caso contrario), o mantenerlo actualizado en S20.
  - Agregar `UNIQUE ("FK_id_usuario", "FK_id_libro", "fecha_prestamo")`.

---

### 3.6. Tabla `devolucion`

- **Atributos en `init/01_esquema.sql`:** `FK_id_prestamo`, `FK_id_ejemplar`, `estado_devolucion`, `fecha_devolucion`.
- **Claves candidatas:**
  - **PK declarada en el DDL actual:** `(FK_id_prestamo, FK_id_ejemplar)`.
  - **Clave candidata según la regla del negocio:** `(FK_id_prestamo)` *(un préstamo corresponde a un solo libro prestado y puede tener como máximo una devolución registrada)*.
- **Dependencia funcional y regla:**
  - `FK_id_prestamo → FK_id_ejemplar, estado_devolucion, fecha_devolucion` *(cada préstamo devuelto tiene una única fecha de devolución, un único ejemplar entregado y un estado de devolución)*.
- **Forma normal más alta:** **1FN** respecto a la PK compuesta declarada `(FK_id_prestamo, FK_id_ejemplar)`, ya que los atributos no primos `fecha_devolucion` y `estado_devolucion` dependen solo de `FK_id_prestamo` (una parte de la clave primaria declarada), lo que constituye una **dependencia parcial (incumple 2FN)**. *(Nota: en la primera versión del esquema, donde existía `PK_id_devolucion` y `UNIQUE (FK_id_prestamo)`, sí estaba en 3FN).*
- **Problemas identificados:**
  1. **PK compuesta sobredimensionada (violación de 2FN):** al declarar `PRIMARY KEY ("FK_id_prestamo", "FK_id_ejemplar")` sin `UNIQUE ("FK_id_prestamo")`, la base permitiría registrar varias devoluciones para un mismo préstamo con distintos ejemplares.
  2. **Dato derivado en `estado_devolucion`:** los valores `'a_tiempo'` y `'tardia'` se obtienen comparando `fecha_devolucion > prestamo.fecha_vencimiento` (solo `'danado'` registra un hecho físico que no sale de las fechas).
- **Evidencia (SQL):**
  ```sql
  -- Comprueba que en los datos cada préstamo tiene a lo sumo 1 devolución:
  SELECT "FK_id_prestamo", count(*)
  FROM biblioteca.devolucion
  GROUP BY "FK_id_prestamo"
  HAVING count(*) > 1;
  -- Resultado: 0 filas (14 devoluciones para 14 préstamos distintos).

  -- Comprueba que 'a_tiempo' y 'tardia' coinciden con comparar las fechas:
  SELECT
      d."FK_id_prestamo",
      p."fecha_vencimiento",
      d."fecha_devolucion",
      d."estado_devolucion" AS estado_guardado,
      CASE
          WHEN d."fecha_devolucion" > p."fecha_vencimiento" THEN 'tardia'
          ELSE 'a_tiempo'
      END AS estado_calculado
  FROM biblioteca.devolucion d
  JOIN biblioteca.prestamo p
      ON p."PK_id_prestamo" = d."FK_id_prestamo";
  -- Resultado: coincide en las 14 filas (12 'a_tiempo' y 2 'tardia': préstamos 1003 y 1023).
  ```
- **Cambio propuesto:**
  - Dejar como clave primaria de `devolucion` únicamente `PRIMARY KEY ("FK_id_prestamo")` para eliminar la dependencia parcial y llevar la tabla a **3FN / FNBC**:
    `devolucion (FK_id_prestamo PK/FK → prestamo, FK_id_ejemplar FK → ejemplares, fecha_devolucion, estado_devolucion)`.
  - Evaluar en S20 si `'a_tiempo'` y `'tardia'` se calculan en una vista a partir de `fecha_devolucion` y `fecha_vencimiento`.

---

### 3.7. Nota sobre `rechazo_carga` (esquemas `carga_libros` y `carga_lectores`)

- **Atributos:** `PK_id_rechazo`, `archivo`, `linea`, `contenido`, `motivo`, `fecha_rechazo`.
- **Clave candidata:** `(PK_id_rechazo)`.
- **Dependencia funcional:** `PK_id_rechazo → archivo, linea, contenido, motivo, fecha_rechazo` *(cada evento de rechazo en la bitácora tiene un identificador único; un mismo archivo puede intentarse cargar más de una vez, por lo que `(archivo, linea)` no es clave candidata)*.
- **Forma normal más alta:** **FNBC / 3FN**. No requiere cambios estructurales.
