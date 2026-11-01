
\set ON_ERROR_STOP on

\if :{?archivo}
\else
  \set archivo /scripts/datos/lectores_semilla.csv
\endif

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DROP TABLE IF EXISTS pg_temp.stg_lectores_raw;
CREATE TEMP TABLE stg_lectores_raw (
    linea BIGINT GENERATED ALWAYS AS IDENTITY,
    contenido TEXT NOT NULL
);

DROP TABLE IF EXISTS pg_temp.stg_lectores;
CREATE TEMP TABLE stg_lectores (
    linea BIGINT,
    contenido TEXT,
    cantidad_campos INTEGER,
    documento TEXT,
    nombres TEXT,
    apellidos TEXT,
    correo TEXT,
    telefono TEXT,
    motivo TEXT
);

BEGIN;

DELETE FROM biblioteca.rechazo_carga
WHERE archivo = :'archivo';

COPY stg_lectores_raw (contenido)
FROM :'archivo'
WITH (FORMAT text);

DELETE FROM stg_lectores_raw
WHERE linea = 1;

INSERT INTO stg_lectores (
    linea, contenido, cantidad_campos,
    documento, nombres, apellidos, correo, telefono
)
SELECT
    linea,
    contenido,
    array_length(string_to_array(contenido, ','), 1),
    btrim(split_part(contenido, ',', 1)),
    btrim(split_part(contenido, ',', 2)),
    btrim(split_part(contenido, ',', 3)),
    btrim(split_part(contenido, ',', 4)),
    btrim(split_part(contenido, ',', 5))
FROM stg_lectores_raw;

UPDATE stg_lectores
SET motivo = CASE
    WHEN cantidad_campos IS DISTINCT FROM 5
        THEN 'tiene ' || COALESCE(cantidad_campos, 0) || ' columnas, se esperaban 5'
    WHEN documento = ''
        THEN 'documento vacío'
    WHEN documento !~ '^[0-9]{6,15}$'
        THEN 'documento no numérico o de longitud inválida'
    WHEN nombres = ''
        THEN 'nombres vacío'
    WHEN char_length(nombres) > 100
        THEN 'nombres supera 100 caracteres'
    WHEN apellidos = ''
        THEN 'apellidos vacío'
    WHEN char_length(apellidos) > 100
        THEN 'apellidos supera 100 caracteres'
    WHEN correo = ''
        THEN 'correo vacío'
    WHEN char_length(correo) > 150
        THEN 'correo supera 150 caracteres'
    WHEN correo !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
        THEN 'correo mal formado'
    WHEN telefono <> ''
         AND telefono !~ '^[0-9]{7,15}$'
        THEN 'teléfono no numérico o de longitud inválida'
    WHEN EXISTS (
        SELECT 1
        FROM biblioteca.usuario u
        WHERE u."documento" = stg_lectores.documento
    )
        THEN 'documento ya existe'
    WHEN EXISTS (
        SELECT 1
        FROM biblioteca.usuario u
        WHERE lower(u."correo") = lower(stg_lectores.correo)
    )
        THEN 'correo ya registrado por otro lector'
    ELSE NULL
END;

UPDATE stg_lectores s
SET motivo = 'documento repetido en el archivo'
WHERE s.motivo IS NULL
  AND EXISTS (
      SELECT 1
      FROM stg_lectores anterior
      WHERE anterior.documento = s.documento
        AND anterior.linea < s.linea
        AND anterior.motivo IS NULL
  );

UPDATE stg_lectores s
SET motivo = 'correo repetido en el archivo'
WHERE s.motivo IS NULL
  AND EXISTS (
      SELECT 1
      FROM stg_lectores anterior
      WHERE lower(anterior.correo) = lower(s.correo)
        AND anterior.linea < s.linea
        AND anterior.motivo IS NULL
  );

INSERT INTO biblioteca.usuario (
    "FK_id_rol",
    "correo",
    "contrasena",
    "nombres",
    "documento",
    "apellidos",
    "telefono"
)
SELECT
    (
        SELECT r."PK_id_rol"
        FROM biblioteca.rol r
        WHERE lower(r."nombre_rol") = 'lector'
        LIMIT 1
    ),
    lower(correo),
    crypt(documento, gen_salt('bf')),
    nombres,
    documento,
    apellidos,
    NULLIF(telefono, '')
FROM stg_lectores
WHERE motivo IS NULL;

INSERT INTO biblioteca.rechazo_carga (
    "archivo",
    "linea",
    "contenido",
    "motivo"
)
SELECT
    :'archivo',
    linea::INTEGER,
    contenido,
    motivo
FROM stg_lectores
WHERE motivo IS NOT NULL;

COMMIT;

SELECT count(*) FILTER (WHERE motivo IS NULL)     AS cargadas,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazadas
FROM stg_lectores;

SELECT linea, motivo, contenido
FROM stg_lectores
WHERE motivo IS NOT NULL
ORDER BY linea;
