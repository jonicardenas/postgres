# Normalización de la base de datos — S20

## 1. Dependencias funcionales y claves candidatas

Una dependencia funcional \(X \rightarrow Y\) indica que el valor de un atributo o conjunto de atributos \(X\) determina un único valor para \(Y\), de acuerdo con las reglas de negocio del sistema.

| Tabla | Claves candidatas | Dependencias funcionales y regla que las justifica |
|---|---|---|
| `rol` | `PK_id_rol`, `nombre_rol` | Cada identificador corresponde a un único nombre de rol. Además, el nombre es único, por lo que también identifica un rol. |
| `usuario` | `PK_id_usuario`, `correo`, `documento` | Cada identificador, correo o documento identifica un único usuario, debido a las restricciones de unicidad. Cada uno determina los demás atributos de la tabla. |
| `libro` | `PK_id_libro`, `isbn` | Cada identificador corresponde a un libro y cada ISBN identifica un único libro. Ambos determinan los demás atributos de la tabla. |
| `ejemplares` | `PK_id_ejemplar` | Cada ejemplar tiene un identificador único que determina el libro al que pertenece y su estado físico. |
| `prestamo` | Original: `PK_id_prestamo`. Propuesta: `(FK_id_usuario, FK_id_libro, fecha_prestamo)`. | El identificador determina los datos del préstamo. Se propone que un usuario no pueda registrar dos préstamos del mismo libro en una misma fecha; por tanto, esa combinación también identificará un préstamo. |
| `devolucion` | Original: `(FK_id_prestamo, FK_id_ejemplar)`. Propuesta: `FK_id_prestamo`. | La regla de negocio establece que cada préstamo tiene como máximo una devolución. Por tanto, el identificador del préstamo determina el ejemplar devuelto, el estado de devolución y la fecha. |

### Precisiones sobre las claves propuestas

- En `prestamo`, la combinación `(FK_id_usuario, FK_id_libro, fecha_prestamo)` no está garantizada por el DDL original. Se incorporará como restricción `UNIQUE`.
- En `devolucion`, el esquema original permite que un mismo préstamo aparezca asociado a más de una devolución porque la clave primaria es compuesta. Se propone cambiarla a `FK_id_prestamo`, haciendo que la estructura garantice la regla de una devolución por préstamo.
- En las demás tablas, las claves candidatas mencionadas están respaldadas por las restricciones de clave primaria o unicidad del esquema original.

**Alcance:** `rechazo_carga` se considera una tabla auxiliar de los procesos de carga y no forma parte de las seis tablas principales del esquema `biblioteca`. Por ello, no se incluye en esta clasificación.

## 2. Forma normal y problemas encontrados

El análisis se realiza a partir de las dependencias funcionales, las claves candidatas y las restricciones del esquema original. Se identifican las siguientes formas normales:

Tabla

Forma normal más alta

Problemas encontrados

rol

FNBC

No se encontraron problemas de normalización.

usuario

FNBC

No se encontraron dependencias parciales ni transitivas.

libro

FNBC

Tiene un atributo derivado (ejemplares_disponibles) que presentó inconsistencias. editorial está en NULL en todos los registros.

ejemplares

FNBC

El estado 'prestado' representa una condición derivada de los préstamos, no una condición física del ejemplar.

prestamo

FNBC

estado_prestamo presentó registros desactualizados. No tiene una restricción UNIQUE sobre la combinación de usuario, libro y fecha del préstamo.

devolucion

1FN

Presenta una dependencia parcial respecto a su clave primaria compuesta, por lo que incumple 2FN.

Análisis de los problemas encontrados

Tabla devolucion: dependencia parcial

La clave primaria original está compuesta por (FK_id_prestamo, FK_id_ejemplar). Sin embargo, la regla de negocio establece que un préstamo tiene como máximo una devolución. Por tanto, FK_id_prestamo determina por sí solo el ejemplar devuelto, la fecha y el estado de devolución.

Esto constituye una dependencia parcial, porque los atributos no primos dependen de una parte de la clave compuesta. En consecuencia, la tabla cumple 1FN, pero no 2FN.

La consulta de diagnóstico no encontró préstamos con más de una devolución: se registraron 14 devoluciones correspondientes a 14 préstamos distintos. Se propone utilizar únicamente FK_id_prestamo como clave primaria para eliminar esta dependencia parcial.

Tabla libro: atributo derivado e inconsistencias

El atributo ejemplares_disponibles puede calcularse a partir de las copias registradas en ejemplares y los préstamos que todavía no tienen devolución.

La comparación entre el valor almacenado y el calculado encontró diferencias en 12 libros. Por ejemplo, el libro con identificador 1 tenía 4 ejemplares registrados, 2 préstamos abiertos y, por tanto, 2 ejemplares disponibles; sin embargo, la columna almacenaba 4.

Adicionalmente, editorial estaba en NULL en todos los registros. Aunque se encontraron autores y categorías repetidos, esta repetición no representa por sí sola una violación de las formas normales.

Tabla ejemplares: estado derivado

Se encontraron 17 préstamos abiertos y ningún ejemplar marcado como 'prestado', aunque todos los ejemplares figuraban como 'disponible'.

Esto evidencia que el estado de préstamo no se estaba sincronizando con la tabla de ejemplares. Se propone reservar estado para la condición física de la copia y determinar si está prestada mediante las relaciones entre préstamos y devoluciones.

Tabla prestamo: estado desactualizado

La consulta de verificación encontró dos préstamos, identificados como 1007 y 1021, cuyo estado almacenado era 'activo', aunque su fecha de vencimiento había pasado el 9 de noviembre de 2026 y no tenían devolución registrada.

Esto evidencia que estado_prestamo es un dato derivable de las fechas y de la existencia de una devolución, y que su almacenamiento puede generar inconsistencias si no se actualiza.

También se identificó la ausencia de una restricción UNIQUE sobre (FK_id_usuario, FK_id_libro, fecha_prestamo), por lo que se propone incorporarla para evitar registros duplicados según esa regla de negocio.

Conclusión del análisis

Las tablas rol, usuario, libro, ejemplares y prestamo cumplen FNBC según las dependencias funcionales identificadas. En devolucion se encontró una dependencia parcial que impide cumplir 2FN; el cambio de su clave primaria permitirá eliminarla.

Los atributos derivados y los datos desactualizados identificados en libro, ejemplares y prestamo se tratarán mediante las decisiones de normalización y desnormalización descritas en el siguiente apartado.

## 3. Desnormalizaciones deliberadas

Se decidió conservar determinados atributos derivados o redundantes por razones de compatibilidad con los procesos de carga y los scripts existentes. Su permanencia requiere mecanismos de actualización y verificación para reducir el riesgo de inconsistencias.

3.1. libro.ejemplares_disponibles

Se conserva este atributo porque el script scripts/carga-libros.sql lo utiliza explícitamente durante la inserción de los libros. Eliminarlo implicaría modificar ese proceso de carga y los componentes que esperan encontrar la columna.

Su valor puede calcularse a partir del total de ejemplares físicos asociados al libro, menos los préstamos que todavía no tienen devolución registrada.

Mantenimiento y verificación:

Durante la normalización se recalculará el valor almacenado utilizando las tablas ejemplares, prestamo y devolucion.

Se utilizará la vista de verificación descuadre para identificar libros cuyo valor almacenado no coincida con el cálculo real.

Para el Hito 4 se podrá implementar un mecanismo de actualización automática mediante triggers cuando se registren préstamos o devoluciones.

Se conserva, por tanto, como una desnormalización deliberada para mantener la compatibilidad con el proceso de carga, aunque requiere controles de consistencia.

3.2. prestamo.estado_prestamo

Se decidió conservar esta columna para mantener la compatibilidad con scripts/datos-prueba.sql y con la estructura actual del proyecto.

El estado puede determinarse mediante las siguientes reglas:

devuelto: existe una devolución asociada al préstamo.

vencido: no existe devolución y la fecha de vencimiento es anterior a la fecha actual.

activo: no existe devolución y la fecha de vencimiento no ha pasado.

Mantenimiento y verificación:

Durante la normalización se actualizará el estado almacenado según estas reglas.

Se utilizará la vista biblioteca.v_verificacion_estado_prestamo para comparar el estado guardado con el calculado y detectar diferencias.

En el Hito 4 se evaluará un mecanismo de actualización automática para los eventos que modifican los préstamos.

Debe tenerse en cuenta que un trigger ejecutado cuando se inserta o modifica una fila no actualiza por sí solo el estado cuando transcurre el tiempo y un préstamo pasa de activo a vencido. Por ello, la vista de verificación seguirá siendo necesaria para detectar esos cambios temporales.

3.3. devolucion.estado_devolucion

Se decidió conservar esta columna para mantener la compatibilidad con scripts/datos-prueba.sql y evitar cambios innecesarios en la estructura que utiliza el proyecto.

El atributo almacena estados que tienen distinto origen:

a_tiempo: se determina cuando la fecha de devolución es menor o igual a la fecha de vencimiento.

tardia: se determina cuando la fecha de devolución es posterior a la fecha de vencimiento.

danado: representa una condición física del ejemplar y no se obtiene únicamente comparando fechas.

Mantenimiento y verificación:

Durante la normalización se conservará el atributo y se comprobará la correspondencia de los estados derivados con las fechas.

Los estados a_tiempo y tardia podrán verificarse mediante una consulta que compare fecha_devolucion con prestamo.fecha_vencimiento.

El estado danado se conservará como información de la condición física registrada.

3.4. Justificación general

Las tres columnas se conservan por compatibilidad con los procesos y scripts existentes, pero su almacenamiento introduce el riesgo de que los valores se desactualicen respecto a la información de origen.

Por esta razón, la normalización contempla recalcular los valores cuando corresponda y disponer de consultas o vistas de verificación. La automatización completa de su mantenimiento se revisará en el Hito 4, sin adelantar la implementación de triggers en esta etapa.