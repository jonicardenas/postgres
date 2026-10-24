# `postgres/scripts/`

Scripts SQL sueltos que **no se ejecutan automáticamente** — quedan
disponibles dentro del contenedor en `/scripts` para correrlos a mano,
cuantas veces se quiera, sin perder los datos existentes.

## Carga del catálogo y lectores

Después de crear el esquema con `postgres/init/01_esquema.sql`, las cargas se
ejecutan en este orden para probar el flujo completo:

```bash
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-libros.sql
docker compose exec postgres psql -U curso -d curso -f /scripts/carga-lectores.sql
docker compose exec postgres psql -U curso -d curso \
  -v archivo=/scripts/datos/libros_semilla_con_errores.csv \
  -f /scripts/carga-libros.sql
docker compose exec postgres psql -U curso -d curso \
  -v archivo=/scripts/datos/lectores_semilla_con_errores.csv \
  -f /scripts/carga-lectores.sql
```

Para volver a probar el archivo limpio, se ejecutan de nuevo los dos primeros
comandos. Las filas rechazadas quedan en `biblioteca.rechazo_carga`.

Los lectores no reciben una contraseña desde el CSV. El script usa el
documento como clave inicial únicamente durante la carga y guarda en
`usuario."contrasena"` el hash bcrypt generado por `pgcrypto`; el documento
en texto plano no se almacena como contraseña.

## Mapeo CSV → esquema y criterios de validación

Antes de ejecutar las cargas, se fijan los siguientes criterios. Los nombres
entre comillas corresponden a las tablas y columnas del esquema
`biblioteca`.

### `libros_semilla.csv`

| Columna del CSV | Tabla.columna destino | Transformación | Regla de validación (motivo) |
|---|---|---|---|
| `isbn` | `libro."isbn"` | `trim()` | No vacío; exactamente 13 dígitos (`isbn vacío`, `isbn no tiene 13 dígitos`); máximo 20 caracteres (`isbn supera 20 caracteres`); no repetido en catálogo (`isbn ya existe en el catálogo`) ni dentro del archivo (`isbn repetido en el archivo`) |
| `titulo` | `libro."titulo"` | `trim()` | No vacío (`título vacío`); máximo 200 caracteres (`título supera 200 caracteres`) |
| `autor` | `libro."autor"` | `trim()` | No vacío (`autor vacío`); máximo 150 caracteres (`autor supera 150 caracteres`) |
| `categoria` | `libro."categoria"` | `trim()` | No vacío (`categoría vacía`); máximo 100 caracteres (`categoría supera 100 caracteres`) |
| `anio_publicacion` | `libro."anio_publicacion"` | `trim()`, conversión a `integer` al insertar | Solo dígitos (`año no numérico`); rango 1450–2100 (`año fuera de rango`) |
| `ejemplares_disponibles` | `libro."ejemplares_disponibles"` | `trim()`, conversión a `integer` al insertar | Entero de hasta 6 dígitos, sin signo positivo (`ejemplares no numérico`); entero ≥ 0 (`ejemplares negativo`) |

La fila completa debe tener exactamente seis columnas; de lo contrario se
rechaza con el motivo `tiene N columnas, se esperaban 6`. Las filas válidas
se insertan en `libro` y cada fila rechazada se registra en
`biblioteca.rechazo_carga`.

### `lectores_semilla.csv`

| Columna del CSV | Tabla.columna destino | Transformación | Regla de validación (motivo) |
|---|---|---|---|
| `documento` | `usuario."documento"` | `trim()` | No vacío (`documento vacío`); entre 6 y 15 dígitos (`documento no numérico o de longitud inválida`); no repetido (`documento ya existe` o `documento o correo repetido en el archivo`) |
| `nombres` | `usuario."nombres"` | `trim()` | No vacío (`nombres vacío`); máximo 100 caracteres (`nombres supera 100 caracteres`) |
| `apellidos` | `usuario."apellidos"` | `trim()` | No vacío (`apellidos vacío`); máximo 100 caracteres (`apellidos supera 100 caracteres`) |
| `correo` | `usuario."correo"` | `trim()`, conversión a minúsculas con `lower()` | No vacío (`correo vacío`); formato `usuario@dominio.ext` (`correo mal formado`); máximo 150 caracteres (`correo supera 150 caracteres`); no repetido (`correo ya registrado por otro lector` o `documento o correo repetido en el archivo`) |
| `telefono` | `usuario."telefono"` | `trim()` | Entre 7 y 15 dígitos (`teléfono no numérico o de longitud inválida`); máximo 20 caracteres (`teléfono supera 20 caracteres`) |

La fila completa debe tener exactamente cinco columnas; de lo contrario se
rechaza con el motivo `tiene N columnas, se esperaban 5`. Para cada lector
válido, el rol destino es `lector` y la contraseña inicial derivada del
`documento` se transforma antes de insertarse:

```sql
crypt(documento, gen_salt('bf')) → usuario."contrasena"
```

Por tanto, el CSV no contiene una columna de contraseña y nunca se guarda el
documento como contraseña en texto plano.