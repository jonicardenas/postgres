# S19 – Parte B: Análisis de normalización del esquema Biblioteca

## 1. Objetivo

Analizar la estructura del esquema `biblioteca` mediante la identificación de claves candidatas, dependencias funcionales y formas normales. También se busca identificar posibles redundancias, inconsistencias y oportunidades de mejora, sustentando el diagnóstico mediante consultas ejecutadas en PostgreSQL.

El análisis se realiza sobre las seis tablas existentes en el esquema:

- `rol`
- `usuario`
- `libro`
- `prestamo`
- `devolucion`
- `rechazo_carga`

No se realizan modificaciones estructurales ni migraciones, ya que estas corresponden a S20 (siguiente taller).

## 2. Criterios de análisis

Para determinar las claves candidatas se consideran las restricciones `PRIMARY KEY` y `UNIQUE`, junto con la obligatoriedad de los atributos mediante `NOT NULL`.

Una dependencia funcional se representa como:

`X → Y`

Esto significa que el valor de X determina un único valor de Y.

Para establecer la forma normal se consideran:

- **Primera forma normal (1FN):** los atributos contienen valores atómicos.
- **Segunda forma normal (2FN):** se cumple 1FN y no existen dependencias parciales de atributos no primos respecto de una parte de una clave candidata.
- **Tercera forma normal (3FN):** se cumple 2FN y no existen dependencias transitivas problemáticas de atributos no primos respecto de las claves candidatas.

Las conclusiones se limitan a las dependencias funcionales justificadas por las restricciones y las reglas de negocio identificadas.

## 3. Análisis por tabla

### 3.1. Tabla `rol`

**Atributos:** `PK_id_rol`, `nombre_rol`.

**Claves candidatas:**
- `PK_id_rol`: clave primaria.
- `nombre_rol`: clave alternativa, debido a la restricción `UNIQUE` y `NOT NULL`.

**Dependencias funcionales:**

`PK_id_rol → nombre_rol`

`nombre_rol → PK_id_rol`

**Regla que las justifica:** cada rol tiene un identificador propio y un nombre que no puede repetirse.

**Forma normal más alta:** 3FN, de acuerdo con las dependencias identificadas.

**Problema identificado:** no se evidencia redundancia estructural ni una violación de las formas normales.

**Evidencia:** la tabla contiene un registro para el rol `lector`. Su nombre tiene una restricción de unicidad.

**Cambio propuesto:** no se requieren modificaciones. Se recomienda conservar la tabla como catálogo independiente para administrar los roles de los usuarios.

### 3.2. Tabla `usuario`

**Atributos:** `PK_id_usuario`, `FK_id_rol`, `correo`, `estado`, `contrasena`, `nombres`, `documento`, `apellidos`, `telefono`.

**Claves candidatas:**
- `PK_id_usuario`: clave primaria.
- `correo`: clave alternativa.
- `documento`: clave alternativa.

**Dependencias funcionales:**

`PK_id_usuario → FK_id_rol, correo, estado, contrasena, nombres, documento, apellidos, telefono`

`correo → PK_id_usuario`

`documento → PK_id_usuario`

**Reglas que las justifican:**
- Cada usuario tiene un identificador único.
- Cada correo pertenece a un solo usuario.
- Cada documento identifica a un solo usuario.
- Cada usuario está asociado a un rol mediante `FK_id_rol`.

Las restricciones `UNIQUE` y `NOT NULL` sobre correo y documento permiten considerarlos claves candidatas.

**Forma normal más alta:** 3FN, de acuerdo con las dependencias identificadas.

**Problema identificado:** no se evidencia una violación de normalización. La información del rol está separada correctamente en la tabla `rol`, evitando almacenar repetidamente su nombre en cada usuario.

**Evidencia:** se encontraron 25 usuarios, todos asociados al rol `lector` y con estado `activo`. Las restricciones de unicidad sobre correo y documento están implementadas.

**Cambio propuesto:** no se requieren cambios estructurales. Se recomienda conservar la relación entre `usuario` y `rol`.

La distribución actual de los datos no permite evaluar el comportamiento con otros roles o estados, pero esto no constituye por sí mismo un problema de normalización.

### 3.3. Tabla `libro`

**Atributos:** `PK_id_libro`, `titulo`, `autor`, `editorial`, `ejemplares_disponibles`, `anio_publicacion`, `categoria`, `isbn`.

**Claves candidatas:**
- `PK_id_libro`: clave primaria.
- `isbn`: clave alternativa.

**Dependencias funcionales:**

`PK_id_libro → titulo, autor, editorial, ejemplares_disponibles, anio_publicacion, categoria, isbn`

`isbn → PK_id_libro`

**Reglas que las justifican:**
- Cada libro tiene un identificador único.
- Cada ISBN identifica un único registro de libro.
- El ISBN no puede repetirse.

**Forma normal más alta:** 3FN, de acuerdo con las dependencias identificadas.

**Problemas identificados:**

1. El atributo `editorial` no contiene información en los 32 registros consultados.
2. Los valores de `autor` se repiten entre distintos libros. Gabriel García Márquez aparece en cuatro registros y Jorge Luis Borges en tres. Esta repetición no demuestra por sí sola una violación de normalización.
3. El atributo `categoria` también presenta valores repetidos, lo cual es esperable cuando varios libros pertenecen a una misma categoría.
4. No existe una tabla independiente de ejemplares físicos en el esquema actual. Por lo tanto, no se puede comprobar si `ejemplares_disponibles` corresponde a un inventario calculado o a una cantidad administrada directamente.

**Evidencia:** se consultaron los 32 libros, encontrando 30 autores distintos, nueve categorías y ningún valor no nulo en `editorial`. Los ejemplares disponibles presentan valores entre 1 y 6.

**Cambio propuesto:**
- Completar los datos de editorial cuando se disponga de información confiable.
- Mantener autor y categoría como atributos mientras no exista una regla de negocio que justifique separarlos.
- Revisar cómo se administra la cantidad de ejemplares disponibles y si en el futuro se requiere registrar cada copia física por separado.

No se propone eliminar atributos ni crear tablas adicionales en esta etapa.

### 3.4. Tabla `prestamo`

**Atributos:** `PK_id_prestamo`, `FK_id_usuario`, `FK_id_libro`, `fecha_prestamo`, `estado_prestamo`, `fecha_vencimiento`.

**Clave candidata:**
- `PK_id_prestamo`: clave primaria.

**Dependencia funcional:**

`PK_id_prestamo → FK_id_usuario, FK_id_libro, fecha_prestamo, estado_prestamo, fecha_vencimiento`

**Regla que la justifica:** cada préstamo tiene un identificador único que determina el usuario, el libro, las fechas y el estado correspondiente.

**Forma normal más alta:** 3FN, de acuerdo con las dependencias identificadas.

**Problema identificado:** se encontraron inconsistencias entre el estado almacenado y la fecha de vencimiento.

La consulta de los 31 préstamos permitió identificar dos registros que aparecen como `activo`, aunque su fecha de vencimiento ya pasó:

- Préstamo 1007: vencimiento el 9 de noviembre de 2026.
- Préstamo 1021: vencimiento el 9 de noviembre de 2026.

Ambos registros no tienen una devolución asociada.

Esto indica que el estado almacenado no se actualiza automáticamente al superar la fecha de vencimiento.

**Evidencia:** se comparó `estado_prestamo` con la existencia de una devolución y con la fecha de vencimiento de cada préstamo.

**Cambio propuesto:** evaluar el cálculo del estado mediante una consulta o vista que considere la existencia de una devolución y la fecha de vencimiento.

La regla de cálculo sería:

- Si existe una devolución, el préstamo está `devuelto`.
- Si no existe devolución y la fecha de vencimiento ya pasó, está `vencido`.
- Si no existe devolución y la fecha de vencimiento todavía no pasa, está `activo`.

Se debe aclarar que esta situación representa un problema de consistencia de los datos y no demuestra por sí misma una violación de 3FN. El estado también podría conservarse como atributo almacenado si se define un mecanismo confiable para actualizarlo.

### 3.5. Tabla `devolucion`

**Atributos:** `PK_id_devolucion`, `FK_id_prestamo`, `estado_devolucion`, `fecha_devolucion`.

**Claves candidatas:**
- `PK_id_devolucion`: clave primaria.
- `FK_id_prestamo`: clave alternativa, debido a que es obligatorio y tiene una restricción `UNIQUE`.

**Dependencias funcionales:**

`PK_id_devolucion → FK_id_prestamo, estado_devolucion, fecha_devolucion`

`FK_id_prestamo → PK_id_devolucion, estado_devolucion, fecha_devolucion`

**Reglas que las justifican:**
- Cada devolución tiene un identificador único.
- Un préstamo puede tener como máximo una devolución registrada.
- Cada devolución corresponde a un préstamo existente.

**Forma normal más alta:** 3FN, de acuerdo con las dependencias identificadas.

**Problema identificado:** el atributo `estado_devolucion` puede obtenerse comparando la fecha de devolución con la fecha de vencimiento del préstamo relacionado.

**Evidencia:** se analizaron los 14 registros de devolución. En todos los casos, el estado almacenado coincide con el resultado de comparar ambas fechas:
- 12 devoluciones fueron realizadas a tiempo.
- 2 devoluciones fueron tardías.

No se encontraron diferencias entre el estado registrado y el calculado.

**Cambio propuesto:** evaluar si `estado_devolucion` debe calcularse mediante una consulta o vista que relacione las tablas `devolucion` y `prestamo`.

También puede conservarse como dato histórico, siempre que se garantice su coherencia con las fechas correspondientes.

No se considera necesario modificar la estructura actual únicamente por esta observación.

### 3.6. Tabla `rechazo_carga`

**Atributos:** `PK_id_rechazo`, `archivo`, `linea`, `contenido`, `motivo`, `fecha_rechazo`.

**Clave candidata:**
- `PK_id_rechazo`: clave primaria.

**Dependencia funcional:**

`PK_id_rechazo → archivo, linea, contenido, motivo, fecha_rechazo`

**Regla que la justifica:** cada rechazo de carga tiene un identificador único que permite registrar el archivo, la línea, el contenido, el motivo y la fecha del rechazo.

**Forma normal más alta:** 3FN, de acuerdo con las dependencias identificadas.

**Problema identificado:** no se evidencia una violación de normalización. Se evaluó si la combinación de `archivo` y `linea` podría identificar un rechazo, pero no existe una restricción que garantice esa unicidad.

**Evidencia:** se encontraron 41 rechazos distribuidos en seis archivos. No hubo pares repetidos de archivo y línea. Se identificaron 20 motivos diferentes y 41 contenidos diferentes.

La ausencia de duplicados en los datos actuales no demuestra que `(archivo, linea)` sea una clave candidata, ya que un mismo archivo podría procesarse nuevamente y producir otro rechazo para la misma línea.

**Cambio propuesto:** no se requieren modificaciones. Se recomienda conservar `PK_id_rechazo` como identificador principal y no declarar `archivo, linea` como clave única sin una regla de negocio que lo justifique.

## 4. Resumen general

| Tabla | Claves candidatas | Forma normal | Hallazgo principal |
|---|---|---|---|
| `rol` | PK_id_rol, nombre_rol | 3FN | Sin problemas identificados |
| `usuario` | PK_id_usuario, correo, documento | 3FN | Sin problemas de normalización identificados |
| `libro` | PK_id_libro, isbn | 3FN | Editorial sin información y revisión del inventario |
| `prestamo` | PK_id_prestamo | 3FN | Dos préstamos activos con fecha de vencimiento superada |
| `devolucion` | PK_id_devolucion, FK_id_prestamo | 3FN | Estado calculable mediante fechas; datos coherentes |
| `rechazo_carga` | PK_id_rechazo | 3FN | Sin problemas de normalización identificados |

La clasificación en 3FN corresponde a las dependencias funcionales identificadas y justificadas en este análisis. Pueden existir otras reglas de negocio que deban evaluarse posteriormente.

## 5. Conclusión

El análisis permitió identificar que las seis tablas del esquema `biblioteca` cuentan con claves primarias y relaciones mediante claves foráneas que permiten organizar la información de manera estructurada.

También se identificaron claves candidatas alternativas en las tablas `rol`, `usuario`, `libro` y `devolucion`, respaldadas por restricciones de unicidad.

No se encontraron dependencias parciales ni dependencias transitivas problemáticas entre los atributos de las tablas, considerando las dependencias funcionales justificadas. Por esta razón, se clasifican en tercera forma normal (3FN).

Las principales oportunidades de mejora están relacionadas con la calidad y consistencia de los datos, especialmente el atributo `estado_prestamo`, y con la ausencia de información de editorial en los registros de libros.

Se recomienda conservar la estructura actual y evaluar posteriormente las mejoras identificadas, sin realizar modificaciones que no estén respaldadas por reglas claras del negocio.

## 6. Evidencias consultadas

Las conclusiones se respaldan en las siguientes consultas ejecutadas sobre PostgreSQL:

1. Consulta de restricciones y claves de las seis tablas, mediante `information_schema.table_constraints` y `pg_constraint`.
2. Consulta de atributos, tipos de datos, obligatoriedad y valores predeterminados, mediante `information_schema.columns`.
3. Consulta de valores repetidos de autor, editorial, categoría y ejemplares disponibles en `biblioteca.libro`.
4. Consulta de estados de préstamo, existencia de devoluciones y fechas de vencimiento.
5. Consulta individual de préstamos y sus devoluciones.
6. Consulta de comparación entre `estado_devolucion` y el estado calculado a partir de las fechas.
7. Consulta de distribución de usuarios por rol y estado.
8. Consulta de rechazos agrupados por archivo y línea, y conteo de motivos y contenidos diferentes.

Las consultas se ejecutaron sin modificar los datos ni la estructura de la base de datos.