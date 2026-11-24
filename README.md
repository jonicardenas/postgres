# Proyecto

Nombres:
Jhon Esteban Acosta Gutierrez 25183888
Andres Mauricio Lopez Garcia 2418048
Joan Nicolás Cárdenas Bastidas 2540684
Jonathan David Borrero Viveros  2520360

## Qué hay en el repositorio

```
docker-compose.yml          PostgreSQL 16 y pgAdmin
.env.example                variables de entorno (se puede copiar a .env, pero no es obligatorio)
init/01_esquema.sql         esquema `biblioteca` normalizado (3FN / FNBC) y vistas de verificación
scripts/carga-libros.sql    carga y validación de libros y ejemplares
scripts/carga-lectores.sql  carga y validación de lectores
scripts/datos-prueba.sql    31 préstamos y 14 devoluciones de prueba (S16 / S20)
scripts/reportes.sql        los 4 reportes del proyecto sobre `biblioteca` (S16 / S20)
scripts/normalizacion.sql   migración y verificación del esquema para el Hito 3 (S20)
scripts/datos/              CSV semilla, CSV con errores y nuestros CSV propios
S20/documento_s20.md        documento de normalización del Hito 3 (antes y después)
assets/                     evidencias y salidas de verificación de los reportes
```

## Cómo levantar el contenedor

Hay que tener Docker Desktop abierto y correr los comandos desde la raíz del repositorio.

```bash
cp .env.example .env            # opcional
docker compose up -d postgres   # primera vez: crea la base y ejecuta init/01_esquema.sql
docker compose ps               # esperar a que postgres esté "healthy"
docker compose logs postgres    # si el esquema tuviera un error, se ve aquí
docker compose exec postgres psql -U curso -d curso -c '\dt biblioteca.*'
```

El último comando debe listar las tablas `rol`, `usuario`, `libro`, `ejemplares`, `prestamo` y `devolucion`.
Si se quiere usar pgAdmin: `docker compose up -d pgadmin` y abrir http://localhost:5050.

Lo que hay en `init/` solo se ejecuta cuando la carpeta `data/` está vacía, así que cada vez que cambiemos `01_esquema.sql` toca borrar los datos y volver a levantar:

```bash
docker compose down
rm -rf data/pgdata          # PowerShell: Remove-Item -Recurse -Force data\pgdata
docker compose up -d postgres
```

## Cómo probar las cargas

Corrimos los scripts en este orden. Cada uno muestra cuántas filas se cargaron, cuántas se rechazaron, el conteo por motivo y el detalle de cada fila rechazada:

```bash
# 1. libros limpio (32 cargadas)
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-libros.sql
# 2. libros con errores (0 cargadas, 8 rechazadas)
docker compose exec postgres psql -U curso -d curso \
  -v archivo=/scripts/datos/libros_semilla_con_errores.csv -f /scripts/carga-libros.sql
# 3. lectores limpio (20 cargados)
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-lectores.sql
# 4. lectores con errores (0 cargados, 6 rechazados)
docker compose exec postgres psql -U curso -d curso \
  -v archivo=/scripts/datos/lectores_semilla_con_errores.csv -f /scripts/carga-lectores.sql
# 5. CSV propios (5 válidas y 3 rechazadas en cada uno)
docker compose exec postgres psql -U curso -d curso \
  -v archivo=/scripts/datos/libros_propio.txt -f /scripts/carga-libros.sql
docker compose exec postgres psql -U curso -d curso \
  -v archivo=/scripts/datos/lectores_propio.txt -f /scripts/carga-lectores.sql
# Bitácora de rechazos
docker compose exec postgres psql -U curso -d curso \
  -c 'SELECT archivo, linea, motivo, contenido FROM carga_libros.rechazo_carga ORDER BY fecha_rechazo, linea'
```

La bitácora de lectores se consulta de la misma forma en
`carga_lectores.rechazo_carga`.

Los `\` al final de línea son de bash. En PowerShell hay que escribir cada comando en una sola línea (o usar el acento grave `` ` `` en lugar de `\`).

Si se repite una carga, los registros existentes no se duplican: los libros se rechazan por «isbn ya existe en el catálogo» y los lectores por «documento ya existe». Comprobamos este comportamiento repitiendo la carga de `lectores_semilla.csv`: en la primera ejecución se insertaron 20 lectores y no hubo rechazos; en la segunda se insertaron 0 y se rechazaron los 20 registros por documento ya existente.

Los CSV de lectores no traen contraseña. Como el esquema la exige, el script usa el documento como clave inicial y guarda solo el hash bcrypt que genera `pgcrypto` (`crypt(documento, gen_salt('bf'))`), así que la clave nunca queda en texto plano.

## Mapeo CSV → esquema

Cada script lee el archivo completo como texto en tablas de staging y ahí marca cada fila con un motivo de rechazo usando un `UPDATE … SET motivo = CASE …` (gana la primera regla que falla). Las cargas crean sus propios esquemas (`carga_lectores` y `carga_libros`) dentro de los scripts, como en el demo, para que sus tablas de paso y `rechazo_carga` no aparezcan en `public` ni en `biblioteca`. Antes de cada ejecución vacían y reutilizan las tablas de staging. Después pasan a las tablas finales de `biblioteca` las filas sin motivo con un `INSERT … SELECT`. Todo va dentro de un `BEGIN … COMMIT`. A todos los campos se les aplica `trim()`.

### Libros (`isbn,titulo,autor,categoria,anio_publicacion,ejemplares_disponibles`)

| Columna del CSV | Tabla.columna destino | Transformación | Regla de validación (motivo) |
|---|---|---|---|
| (línea completa) | — | — | exactamente 6 campos (`tiene N columnas, se esperaban 6`) |
| `isbn` | `libro.isbn` | — | no vacío (`isbn vacío`); 13 dígitos (`isbn no tiene 13 dígitos`); no existe en el catálogo (`isbn ya existe en el catálogo`); no repetido antes en el archivo (`isbn repetido en el archivo`) |
| `titulo` | `libro.titulo` | — | no vacío (`título vacío`); ≤ 200 (`título supera 200 caracteres`) |
| `autor` | `libro.autor` | — | no vacío (`autor vacío`); ≤ 150 (`autor supera 150 caracteres`) |
| `categoria` | `libro.categoria` | — | no vacía (`categoría vacía`); ≤ 100 (`categoría supera 100 caracteres`) |
| `anio_publicacion` | `libro.anio_publicacion` | `::integer` | 1–4 dígitos (`año no numérico`); entre 1400 y 2100, igual que `ck_libro_anio` (`año fuera de rango`) |
| `ejemplares_disponibles` | `libro.ejemplares_disponibles` | `::integer` | no negativo (`ejemplares negativo`); solo dígitos (`ejemplares no numérico`); ≤ 9 dígitos (`ejemplares demasiado grande`) |

Cada libro válido también crea en `ejemplares` una fila por cada unidad indicada
en `ejemplares_disponibles`, asociada mediante `FK_id_libro` y con estado inicial
`disponible`. Las filas rechazadas no crean libros ni ejemplares.

### Lectores (`documento,nombres,apellidos,correo,telefono`)

| Columna del CSV | Tabla.columna destino | Transformación | Regla de validación (motivo) |
|---|---|---|---|
| (línea completa) | — | — | exactamente 5 campos (`tiene N columnas, se esperaban 5`) |
| `documento` | `usuario.documento` | — | no vacío (`documento vacío`); 6–15 dígitos (`documento no numérico o de longitud inválida`); no existe (`documento ya existe`); no repetido en el archivo (`documento repetido en el archivo`) |
| `nombres` | `usuario.nombres` | — | no vacío (`nombres vacío`); ≤ 100 (`nombres supera 100 caracteres`) |
| `apellidos` | `usuario.apellidos` | — | no vacío (`apellidos vacío`); ≤ 100 (`apellidos supera 100 caracteres`) |
| `correo` | `usuario.correo` | `lower()` | no vacío (`correo vacío`); ≤ 150 (`correo supera 150 caracteres`); formato `a@b.c` (`correo mal formado`); no existe, sin distinguir mayúsculas (`correo ya registrado por otro lector`); no repetido en el archivo (`correo repetido en el archivo`) |
| `telefono` | `usuario.telefono` | vacío → `NULL` | si viene, 7–15 dígitos (`teléfono no numérico o de longitud inválida`) |
| (no viene en el CSV) | `usuario.FK_id_rol` | rol `lector` | — |
| (no viene en el CSV) | `usuario.contrasena` | `crypt(documento, gen_salt('bf'))` | — |

## Criterios por tipo de error

El criterio que seguimos fue el mismo para todos los casos. Corregimos solo lo que es mecánico y no cambia el significado del dato (quitar espacios con `trim` y pasar el correo a minúsculas). Todo lo demás se rechaza y queda en la bitácora, porque el dato falta o no hay forma de saber cuál era el valor correcto. Tampoco actualizamos registros que ya existen: un duplicado se rechaza para no cambiar el inventario ni los datos de un lector sin que nadie lo haya pedido.

| # | Archivo, línea | Problema | Decisión | Motivo registrado | Por qué |
|---|---|---|---|---|---|
| 1 | libros, 2 | ISBN que ya está en el catálogo | Rechazar | isbn ya existe en el catálogo | Sumar ejemplares sin confirmación alteraría el inventario; permite repetir la carga sin duplicar |
| 2 | libros, 3 | Título vacío | Rechazar | título vacío | No se puede inventar |
| 3 | libros, 4 | Texto «dos» donde van los ejemplares disponibles | Rechazar | ejemplares no numérico | No se puede interpretar como una cantidad numérica |
| 4 | libros, 5 | Año en números romanos (MCMXLIX) | Rechazar | año no numérico | Convertirlo sería adivinar |
| 5 | libros, 6 | 7 columnas en vez de 6 | Rechazar | tiene 7 columnas, se esperaban 6 | No se sabe qué campo sobra |
| 6 | libros, 7 | Autor vacío | Rechazar | autor vacío | Obligatorio en el esquema |
| 7 | libros, 8 | ISBN vacío | Rechazar | isbn vacío | Es la clave natural del libro |
| 8 | libros, 9 | Ejemplares negativos | Rechazar | ejemplares negativo | No se corrige el signo |
| 9 | lectores, 2 | Documento ya registrado | Rechazar | documento ya existe | Es el identificador único de la persona |
| 10 | lectores, 3 | Correo vacío | Rechazar | correo vacío | Obligatorio y único |
| 11 | lectores, 4 | Correo sin `@` | Rechazar | correo mal formado | No se puede adivinar el correo real |
| 12 | lectores, 5 | Teléfono «tres-cero-cero» | Rechazar | teléfono no numérico o de longitud inválida | Aunque el teléfono es opcional, un valor inválido no se borra en silencio |
| 13 | lectores, 6 | Documento vacío | Rechazar | documento vacío | Obligatorio y único |
| 14 | lectores, 7 | Nombres vacío | Rechazar | nombres vacío | Obligatorio |
| extra | cualquiera | Espacios sobrantes; correo en mayúsculas | Corregir | — | Cambio mecánico (`trim`, `lower`) |
| extra | libros propio, 9 | ISBN con guiones (`978-958-…`) | Rechazar | isbn no tiene 13 dígitos | Se podría normalizar, pero el grupo decidió exigir el formato exacto para ser consistente |

## CSV propios

Armamos `scripts/datos/libros_propio.txt` y `scripts/datos/lectores_propio.txt`. Cada uno tiene 5 filas válidas que no están en la semilla y 3 filas con errores que no aparecen en los archivos del curso:

| Archivo | Línea | Error nuevo | Motivo registrado |
|---|---|---|---|
| libros | 7 | El mismo ISBN dos veces en el archivo | isbn repetido en el archivo |
| libros | 8 | Año en el futuro (2150) | año fuera de rango |
| libros | 9 | ISBN con guiones | isbn no tiene 13 dígitos |
| lectores | 7 | Mismo documento dos veces en el archivo | documento repetido en el archivo |
| lectores | 8 | Mismo correo con otras mayúsculas (`CARLOS.PEREZ@EMAIL.COM`) | correo repetido en el archivo |
| lectores | 9 | Documento con una letra (`70A7070707`) | documento no numérico o de longitud inválida |

## Salidas de psql de las cargas

Salidas de `psql` de las cargas, corridas sobre una base recién creada y en el orden de arriba. Para no alargar el informe dejamos solo el resumen `cargadas | rechazadas` y las filas rechazadas con su motivo; el resto de la salida son los conteos de `COPY`, `UPDATE` e `INSERT`.

### Carga 1: libros_semilla.csv (limpio)

```
 cargadas | rechazadas 
----------+------------
       32 |          0
(1 row)
```

### Carga 2: libros_semilla_con_errores.csv

```
 cargadas | rechazadas 
----------+------------
        0 |          8
(1 row)
 linea |              motivo              |                                          contenido                                          
-------+----------------------------------+---------------------------------------------------------------------------------------------
     2 | isbn ya existe en el catálogo    | 9780000000001,Cien años de soledad (edición duplicada),Gabriel García Márquez,Novela,1967,2
     3 | título vacío                     | 9780000000033,,Julio Cortázar,Novela,1963,3
     4 | ejemplares no numérico | 9780000000034,Relato sin ejemplares numéricos,Autor de Prueba,Novela,2003,dos
     5 | año no numérico                  | 9780000000035,Relato con año inválido,Autor de Prueba,Novela,MCMXLIX,2
     6 | tiene 7 columnas, se esperaban 6 | 9780000000036,Relato con columna de más,Autor de Prueba,Novela,1999,2,columna_sobrante
     7 | autor vacío                      | 9780000000037,Relato sin autor,,Novela,2005,1
     8 | isbn vacío                       | ,Relato sin ISBN,Autor de Prueba,Novela,2010,1
     9 | ejemplares negativo              | 9780000000038,Relato con ejemplares negativos,Autor de Prueba,Novela,2015,-3
(8 rows)
```

### Carga 3: lectores_semilla.csv (limpio)

```
 cargadas | rechazadas 
----------+------------
       20 |          0
(1 row)
```

### Carga 4: lectores_semilla_con_errores.csv

```
 cargadas | rechazadas 
----------+------------
        0 |          6
(1 row)
 linea |                   motivo                    |                                         contenido                                         
-------+---------------------------------------------+-------------------------------------------------------------------------------------------
     2 | documento ya existe                         | 1000000001,Mariana,Gómez Rojas (duplicado),mariana.gomez@correo-ejemplo.edu.co,3001000001
     3 | correo vacío                                | 1000000021,Carlos,Peña Londoño,,3001000021
     4 | correo mal formado                          | 1000000022,Diana,Salgado Cuervo,diana.salgado-arroba-correo-ejemplo.edu.co,3001000022
     5 | teléfono no numérico o de longitud inválida | 1000000023,Jorge,Restrepo Vélez,jorge.restrepo@correo-ejemplo.edu.co,tres-cero-cero
     6 | documento vacío                             | ,Sin Documento,Prueba Prueba,sin.documento@correo-ejemplo.edu.co,3001000024
     7 | nombres vacío                               | 1000000025,,Sin Nombre,sin.nombre@correo-ejemplo.edu.co,3001000025
(6 rows)
```

### Carga 5: libros_propio.txt (CSV propio)

```
 cargadas | rechazadas 
----------+------------
        5 |          3
(1 row)
 linea |           motivo            |                                                contenido                                                
-------+-----------------------------+---------------------------------------------------------------------------------------------------------
     7 | isbn repetido en el archivo | 9789580400011,El amor en los tiempos del cólera (Duplicado en CSV),Gabriel García Márquez,Novela,1985,2
     8 | año fuera de rango          | 9789580400066,Libro del Futuro,Autor Viajero,Ciencia Ficción,2150,1
     9 | isbn no tiene 13 dígitos    | 978-958-04-0007-3,Libro con ISBN con guiones,Autor Desconocido,Ensayo,2020,3
(3 rows)
```

### Carga 6: lectores_propio.txt (CSV propio)

```
 cargadas | rechazadas 
----------+------------
        5 |          3
(1 row)
 linea |                    motivo                    |                                contenido                                
-------+----------------------------------------------+-------------------------------------------------------------------------
     7 | documento repetido en el archivo             | 1010101010,Carlos Duplicado,Pérez,carlos.duplicado@email.com,3001234567
     8 | correo repetido en el archivo                | 3030303031,Correo Repetido,Prueba,CARLOS.PEREZ@EMAIL.COM,3001234567
     9 | documento no numérico o de longitud inválida | 70A7070707,Documento Con Letras,Prueba,doc.letras@email.com,3001234567
(3 rows)
```

## Prueba de la última línea de defensa

Para comprobar que las restricciones `CHECK` del esquema funcionan como última línea de defensa, realizamos una prueba controlada con un archivo temporal llamado `libro_check_prueba.csv`.

El archivo contenía un libro con el valor `-1` en el campo `ejemplares_disponibles`, que normalmente debe ser rechazado por la validación del script.

Primero intentamos desactivar la regla `ejemplares negativo` del `CASE`, pero la expresión regular de validación seguía rechazando el valor negativo. Por eso, para la segunda prueba modificamos temporalmente la expresión regular para permitir números negativos y desactivamos la regla correspondiente del `CASE`.

De esta manera, el registro llegó al `INSERT` y PostgreSQL lo rechazó mediante la restricción:

```text
ERROR: new row for relation "libro" violates check constraint "ck_libro_ejemplares"
```

**¿Qué pasa con las demás filas?**

El `INSERT ... SELECT` es una sola sentencia. Si una fila incumple una restricción, la sentencia completa falla. Como el script utiliza `ON_ERROR_STOP` y una transacción, se revierte la operación y no se insertan parcialmente los registros.

**¿Qué pasa con la bitácora?**

La ejecución que provoca el error de `CHECK` también se revierte. Por tanto, no se guarda un nuevo rechazo correspondiente a esa ejecución. El rechazo que encontramos después corresponde al primer intento, en el que la validación del script todavía detectaba el valor negativo.

**Comprobación posterior**

Después de la prueba restauramos el script original y verificamos que:

- El catálogo conserva sus 37 libros.
- El libro temporal de prueba no fue insertado.
- La bitácora conserva un rechazo correspondiente al primer intento.

Con esta prueba comprobamos que las restricciones `CHECK` protegen la tabla incluso si una validación del script falla o se desactiva accidentalmente. Sin embargo, también observamos que un error en una sola fila puede cancelar toda la sentencia de inserción y provocar que no se registre la bitácora de esa ejecución.

Por eso es importante mantener las validaciones del `CASE` en los scripts de carga y las restricciones del esquema como última defensa.

## Hito 3 (S20): normalización, migración y reportes

El análisis completo de formas normales, dependencias funcionales, cambios aplicados y desnormalizaciones justificadas está en `S20/documento_s20.md`.

### 1. Probar `init/01_esquema.sql` en una base limpia aparte

Para verificar que el esquema inicial actualizado corre limpio sin borrar la base `curso`:

```bash
docker compose exec postgres psql -U curso -d curso -c "CREATE DATABASE prueba_init;"
docker compose exec postgres psql -U curso -d prueba_init -f /docker-entrypoint-initdb.d/01_esquema.sql
docker compose exec postgres psql -U curso -d curso -c "DROP DATABASE prueba_init;"
```

### 2. Cargar datos de prueba, correr la migración y verificar los reportes

Con los libros y lectores ya cargados en `biblioteca`:

```bash
# 1. Cargar los 31 préstamos y 14 devoluciones de prueba
docker compose exec postgres psql -U curso -d curso -f /scripts/datos-prueba.sql

# 2. Aplicar/verificar la migración del Hito 3 y las vistas de descuadre (0 filas)
docker compose exec postgres psql -U curso -d curso -f /scripts/normalizacion.sql

# 3. Correr los 4 reportes de S16 sobre el esquema normalizado
docker compose exec postgres psql -U curso -d curso -f /scripts/reportes.sql
```