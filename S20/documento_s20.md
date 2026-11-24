# Normalización de la base de datos — S20

## 1. Esquema antes de la normalización

El esquema original de `biblioteca` estaba compuesto por seis tablas principales y una tabla auxiliar:

- `rol`: almacena los roles del sistema.
- `usuario`: registra los usuarios y referencia el rol correspondiente.
- `libro`: almacena la información bibliográfica de cada libro.
- `ejemplares`: registra las copias físicas asociadas a cada libro.
- `prestamo`: registra los préstamos realizados por los usuarios sobre los libros.
- `devolucion`: registra las devoluciones asociadas a los préstamos y a los ejemplares.
- `rechazo_carga`: tabla auxiliar utilizada por los procesos de carga.

**Claves primarias originales:**

| Tabla | Clave primaria |
|---|---|
| `rol` | `PK_id_rol` |
| `usuario` | `PK_id_usuario` |
| `libro` | `PK_id_libro` |
| `ejemplares` | `PK_id_ejemplar` |
| `prestamo` | `PK_id_prestamo` |
| `devolucion` | (`FK_id_prestamo`, `FK_id_ejemplar`) |

**Relaciones entre las tablas principales:**

```text
rol         1 ─── N usuario
usuario     1 ─── N prestamo
libro       1 ─── N prestamo
libro       1 ─── N ejemplares
prestamo    1 ─── N devolucion (según el esquema original)
ejemplares  1 ─── N devolucion
```

La tabla `prestamo` referencia directamente a `usuario` y `libro`, pero no identifica directamente el ejemplar físico prestado. La tabla `devolucion` relaciona el préstamo con el ejemplar devuelto.

Aunque la regla de negocio establece que cada préstamo debe tener como máximo una devolución, la clave primaria compuesta original de `devolucion` permitía registrar más de una fila para un mismo préstamo, siempre que correspondiera a ejemplares diferentes. Esta diferencia motivó uno de los cambios de normalización.

## 2. Dependencias funcionales y claves candidatas

Una dependencia funcional \(X \rightarrow Y\) indica que el valor de un atributo o conjunto de atributos \(X\) determina un único valor para \(Y\), de acuerdo con las reglas de negocio del sistema.

| Tabla | Claves candidatas | Dependencias funcionales y regla que las justifica |
|---|---|---|
| `rol` | `PK_id_rol`, `nombre_rol` | Cada identificador corresponde a un único nombre de rol. Además, el nombre es único, por lo que también identifica un rol. |
| `usuario` | `PK_id_usuario`, `correo`, `documento` | Cada identificador, correo o documento identifica un único usuario, debido a las restricciones de unicidad. Cada uno determina los demás atributos de la tabla. |
| `libro` | `PK_id_libro`, `isbn` | Cada identificador corresponde a un libro y cada ISBN identifica un único libro. Ambos determinan los demás atributos de la tabla. |
| `ejemplares` | `PK_id_ejemplar` | Cada ejemplar tiene un identificador único que determina el libro al que pertenece y su estado físico. |
| `prestamo` | Original: `PK_id_prestamo`. Adicional implementada: (`FK_id_usuario`, `FK_id_libro`, `fecha_prestamo`). | El identificador determina los datos del préstamo. La combinación de usuario, libro y fecha también identifica un préstamo, según la regla de negocio y la restricción `UNIQUE` incorporada durante la migración. |
| `devolucion` | Original: (`FK_id_prestamo`, `FK_id_ejemplar`). Nueva clave primaria implementada: `FK_id_prestamo`. | La regla de negocio establece que cada préstamo tiene como máximo una devolución. Por tanto, el identificador del préstamo determina el ejemplar devuelto, el estado de devolución y la fecha. |

### Precisiones sobre las claves candidatas

- En `prestamo`, la combinación (`FK_id_usuario`, `FK_id_libro`, `fecha_prestamo`) no estaba garantizada por el DDL original. Durante la migración se incorporó una restricción `UNIQUE` para garantizar esta regla de negocio.
- En `devolucion`, la clave primaria original era compuesta y permitía asociar más de una devolución al mismo préstamo. Durante la migración se reemplazó por `FK_id_prestamo`, garantizando como máximo una devolución por préstamo.
- En las demás tablas, las claves candidatas mencionadas están respaldadas por las restricciones de clave primaria o unicidad del esquema original.

**Alcance:** `rechazo_carga` se considera una tabla auxiliar de los procesos de carga y no forma parte de las seis tablas principales del esquema `biblioteca`. Por ello, no se incluye en esta clasificación.

## 3. Forma normal y problemas encontrados

El análisis se realiza a partir de las dependencias funcionales, las claves candidatas y las restricciones del esquema original. Las formas normales identificadas antes de la migración fueron:

| Tabla | Forma normal original | Problema encontrado |
|---|---|---|
| `rol` | FNBC | No se encontraron problemas de normalización. |
| `usuario` | FNBC | No se encontraron dependencias parciales ni transitivas. |
| `libro` | FNBC | `ejemplares_disponibles` presentó inconsistencias por ser un dato derivado. `editorial` estaba en NULL en todos los registros. |
| `ejemplares` | FNBC | El estado `prestado` representaba una condición derivada de los préstamos. |
| `prestamo` | FNBC | Se encontraron estados desactualizados y faltaba una restricción UNIQUE sobre usuario, libro y fecha. |
| `devolucion` | 1FN | Presentaba una dependencia parcial respecto a su clave primaria compuesta, por lo que incumplía 2FN. |

### Análisis de los problemas encontrados

**Tabla `devolucion`: dependencia parcial**

La clave primaria original estaba compuesta por (`FK_id_prestamo`, `FK_id_ejemplar`). Sin embargo, la regla de negocio establece que un préstamo tiene como máximo una devolución. Por tanto, `FK_id_prestamo` determina por sí solo el ejemplar devuelto, la fecha y el estado de devolución.

Esto constituía una dependencia parcial: los atributos no primos dependían de una parte de la clave compuesta. En consecuencia, la tabla cumplía 1FN, pero no 2FN. La consulta de diagnóstico encontró 14 devoluciones correspondientes a 14 préstamos distintos. Durante la migración se reemplazó la clave primaria compuesta por `FK_id_prestamo`, eliminando esta dependencia parcial.

**Tabla `libro`: atributo derivado e inconsistencias**

El atributo `ejemplares_disponibles` puede calcularse a partir de las copias registradas en `ejemplares` y los préstamos que todavía no tienen devolución. En el diagnóstico inicial se encontraron diferencias en 12 libros. Por ejemplo, el libro con identificador 1 tenía 4 ejemplares registrados y 2 préstamos abiertos; por tanto, debía tener 2 ejemplares disponibles, pero la columna almacenaba 4.

En la comprobación realizada durante la migración no se encontraron diferencias entre el valor almacenado y el calculado, por lo que no fue necesario actualizar esta columna. Se creó una vista para detectar posibles descuadres posteriores.

Adicionalmente, `editorial` estaba en NULL en todos los registros del diagnóstico. Aunque se encontraron autores y categorías repetidos, esta repetición no representa por sí sola una violación de las formas normales.

**Tabla `ejemplares`: estado derivado**

En el diagnóstico de S19 se reportaron 17 préstamos abiertos y ningún ejemplar marcado como `prestado`; los ejemplares figuraban como `disponible`. Esto evidenciaba que el estado de la copia no permitía representar de forma confiable su situación frente a los préstamos.

Durante la migración se modificó la restricción `CHECK` de `estado` para admitir únicamente `disponible`, `danado` y `mantenimiento`. También se registró la actualización de 17 ejemplares desde `prestado` a `disponible`. Al finalizar, se verificó que los 131 ejemplares estaban en estado `disponible`.

Se decidió reservar el atributo `estado` para la condición física de la copia y determinar si está prestada mediante las relaciones entre préstamos y devoluciones.

**Tabla `prestamo`: estado desactualizado**

En el diagnóstico de S19 se encontraron dos préstamos, identificados como 1007 y 1021, cuyo estado almacenado era `activo`, aunque su fecha de vencimiento había pasado y no tenían devolución registrada.

Durante la migración se volvió a verificar el estado utilizando la fecha local de Colombia (`America/Bogota`). Se actualizaron tres préstamos que debían figurar como `vencido`. También se incorporó una restricción `UNIQUE` sobre (`FK_id_usuario`, `FK_id_libro`, `fecha_prestamo`) para impedir registros duplicados según la regla de negocio. No se encontraron combinaciones duplicadas entre los 31 préstamos existentes.

**Conclusión del análisis**

Antes de la migración, las tablas `rol`, `usuario`, `libro`, `ejemplares` y `prestamo` cumplían FNBC según las dependencias funcionales identificadas. La tabla `devolucion` cumplía 1FN, pero no 2FN debido a una dependencia parcial respecto a su clave primaria compuesta.

Después de los cambios, la tabla `devolucion` dejó de presentar esa dependencia parcial. Las inconsistencias identificadas en los atributos derivados y estados almacenados se abordaron mediante los cambios estructurales, las actualizaciones y las vistas de verificación descritas en las secciones siguientes.

## 4. Cambios aplicados y migración de datos

Los cambios se aplicaron mediante una migración incremental sobre el esquema `biblioteca`, conservando los registros existentes. Antes de realizarla se generó un respaldo de la base de datos.

Los cambios estructurales fueron:

- **devolucion:** se reemplazó la clave primaria compuesta por una clave primaria basada únicamente en `FK_id_prestamo`. Los 14 registros existentes tenían valores únicos y no nulos en esta columna.
- **prestamo:** se agregó una restricción `UNIQUE` sobre (`FK_id_usuario`, `FK_id_libro`, `fecha_prestamo`). No se encontraron combinaciones duplicadas entre los 31 préstamos existentes.
- **ejemplares:** se modificó la restricción `CHECK` de `estado` para admitir únicamente `disponible`, `danado` y `mantenimiento`. Los 17 ejemplares que figuraban como `prestado` se actualizaron a `disponible`, porque el préstamo se determina mediante los registros abiertos en `prestamo`.

También se actualizaron los estados de tres préstamos que continuaban registrados como `activo`, aunque su fecha de vencimiento ya había pasado. La comparación se realizó utilizando la fecha local de Colombia (`America/Bogota`).

Se crearon dos vistas de verificación:

- `biblioteca.v_descuadre_disponibles`: compara la disponibilidad guardada en `libro` con la calculada a partir de los ejemplares y los préstamos abiertos.
- `biblioteca.v_descuadre_estado_prestamo`: compara el estado almacenado del préstamo con el estado calculado a partir de su fecha de vencimiento y la existencia de una devolución.

**Conteos después de la migración:**

| Tabla | Registros |
|---|---:|
| rol | 1 |
| usuario | 25 |
| libro | 37 |
| ejemplares | 131 |
| prestamo | 31 |
| devolucion | 14 |

La migración no insertó ni eliminó registros de estas tablas. Por tanto, sus cantidades se conservaron durante los cambios estructurales y las actualizaciones de estado. No se modificaron los registros de `rechazo_carga`.

Las vistas de verificación no devolvieron registros al finalizar la migración: no se encontraron descuadres de disponibilidad ni de estado de préstamo en esa comprobación.

## 5. Desnormalizaciones deliberadas

Se conservaron algunos atributos derivados por compatibilidad con los scripts existentes:

**`libro.ejemplares_disponibles`:** se conserva porque `scripts/carga-libros.sql` utiliza esta columna al cargar los libros. Su valor se puede calcular a partir del número de ejemplares físicos y los préstamos que todavía no tienen devolución. La vista `biblioteca.v_descuadre_disponibles` permite detectar diferencias entre el valor almacenado y el calculado. La comprobación posterior a la migración devolvió cero registros.

**`prestamo.estado_prestamo`:** se conserva por compatibilidad con `scripts/datos-prueba.sql`. El estado se puede calcular considerando si el préstamo tiene devolución y, en caso contrario, comparando su fecha de vencimiento con la fecha actual. La vista `biblioteca.v_descuadre_estado_prestamo` permite detectar diferencias. Se corrigieron tres estados durante la migración y la vista no encontró diferencias al finalizar la comprobación.

El cálculo de vencimiento utiliza la fecha local de Colombia para evitar que la zona horaria del servidor adelante la clasificación de los préstamos.

**`devolucion.estado_devolucion`:** se conserva por compatibilidad con los datos y procesos existentes. Los estados `a_tiempo` y `tardia` representan clasificaciones relacionadas con las fechas del préstamo y la devolución, mientras que `danado` registra una condición física del ejemplar. No se creó una vista de verificación específica para esta columna durante la migración.

Estas columnas se mantienen como desnormalizaciones deliberadas. Las vistas permiten detectar inconsistencias, pero no actualizan automáticamente los valores. La automatización de su mantenimiento no forma parte de los cambios aplicados en esta migración.

## 6. Esquema después de la normalización

Después de los cambios, el esquema `biblioteca` queda conformado por las siguientes tablas:

- **rol:** identificada por `PK_id_rol`; `nombre_rol` es único.
- **usuario:** identificada por `PK_id_usuario`; `correo` y `documento` son únicos.
- **libro:** identificada por `PK_id_libro`; `isbn` es único. Se conserva `ejemplares_disponibles` como atributo derivado.
- **ejemplares:** identificada por `PK_id_ejemplar`; cada ejemplar pertenece a un libro. Su estado representa únicamente su condición física.
- **prestamo:** identificado por `PK_id_prestamo`; incluye la restricción única sobre usuario, libro y fecha de préstamo. Se conserva `estado_prestamo`.
- **devolucion:** identificada por `FK_id_prestamo`, que es su clave primaria y referencia el préstamo correspondiente.

La tabla auxiliar `rechazo_carga` se mantiene para registrar los rechazos de los procesos de carga.

Los cambios estructurales realizados permiten eliminar la dependencia parcial identificada en `devolucion` y reforzar la identificación de los préstamos mediante una clave candidata adicional. Se conservó la clave primaria original de `prestamo` y se incorporó una restricción `UNIQUE` sobre usuario, libro y fecha. En `devolucion`, la clave primaria compuesta original se reemplazó por `FK_id_prestamo`, de acuerdo con la regla de una devolución por préstamo.

Las columnas derivadas que se conservaron se documentan como excepciones deliberadas a la eliminación de redundancias, con vistas para verificar su consistencia.

La columna `libro.editorial` se mantiene en el esquema actual; no hizo parte de los cambios aplicados.