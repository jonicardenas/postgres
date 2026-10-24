
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
    WHEN cantidad_campos <> 5
        THEN 'Cantidad de campos distinta de 5'
    WHEN documento !~ '^[0-9]{6,15}$'
        THEN 'Documento debe contener entre 6 y 15 dígitos'
    WHEN nombres = ''
        THEN 'Nombres obligatorios'
    WHEN char_length(nombres) > 100
        THEN 'Nombres superan 100 caracteres'
    WHEN apellidos = ''
        THEN 'Apellidos obligatorios'
    WHEN char_length(apellidos) > 100
        THEN 'Apellidos superan 100 caracteres'
    WHEN correo = ''
        THEN 'Correo obligatorio'
    WHEN char_length(correo) > 150
        THEN 'Correo supera 150 caracteres'
    WHEN correo !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
        THEN 'Formato de correo inválido'
    WHEN telefono <> ''
         AND telefono !~ '^[0-9]{7,15}$'
        THEN 'Teléfono debe tener entre 7 y 15 dígitos'
    WHEN EXISTS (
        SELECT 1
        FROM biblioteca.usuario u
        WHERE u."documento" = stg_lectores.documento
    )
        THEN 'Documento ya existe en Usuario'
    WHEN EXISTS (
        SELECT 1
        FROM biblioteca.usuario u
        WHERE lower(u."correo") = lower(stg_lectores.correo)
    )
        THEN 'Correo ya existe en Usuario'
    ELSE NULL
END;

UPDATE stg_lectores s
SET motivo = 'Documento duplicado dentro del archivo'
WHERE s.motivo IS NULL
  AND EXISTS (
      SELECT 1
      FROM stg_lectores anterior
      WHERE anterior.documento = s.documento
        AND anterior.linea < s.linea
        AND anterior.motivo IS NULL
  );

UPDATE stg_lectores s
SET motivo = 'Correo duplicado dentro del archivo'
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
    correo,
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

SELECT 'Lectores cargados' AS resultado, COUNT(*) AS cantidad
FROM stg_lectores
WHERE motivo IS NULL;

SELECT 'Filas rechazadas' AS resultado, COUNT(*) AS cantidad
FROM stg_lectores
WHERE motivo IS NOT NULL;

SELECT motivo, COUNT(*) AS cantidad
FROM stg_lectores
WHERE motivo IS NOT NULL
GROUP BY motivo
ORDER BY motivo;
