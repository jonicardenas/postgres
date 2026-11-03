
\set ON_ERROR_STOP on

\if :{?archivo}
\else
  \set archivo /scripts/datos/libros_semilla.csv
\endif

DROP SCHEMA IF EXISTS carga_libros CASCADE;
CREATE SCHEMA carga_libros;
SET search_path TO carga_libros, biblioteca;

CREATE TABLE rechazo_carga (
    "PK_id_rechazo" BIGINT GENERATED ALWAYS AS IDENTITY,
    "archivo" TEXT NOT NULL,
    "linea" INTEGER NOT NULL,
    "contenido" TEXT NOT NULL,
    "motivo" TEXT NOT NULL,
    "fecha_rechazo" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_rechazo_carga PRIMARY KEY ("PK_id_rechazo")
);

CREATE TABLE stg_libros_raw (
    linea BIGINT GENERATED ALWAYS AS IDENTITY,
    contenido TEXT NOT NULL
);

CREATE TABLE stg_libros (
    linea BIGINT,
    contenido TEXT,
    cantidad_campos INTEGER,
    isbn TEXT,
    titulo TEXT,
    autor TEXT,
    categoria TEXT,
    anio TEXT,
    ejemplares TEXT,
    motivo TEXT
);

BEGIN;

TRUNCATE stg_libros_raw, stg_libros RESTART IDENTITY;

COPY stg_libros_raw (contenido)
FROM :'archivo'
WITH (FORMAT text);

DELETE FROM stg_libros_raw
WHERE linea = 1;

INSERT INTO stg_libros (
    linea, contenido, cantidad_campos,
    isbn, titulo, autor, categoria,
    anio, ejemplares
)
SELECT
    linea,
    contenido,
    array_length(string_to_array(contenido, ','), 1),
    btrim(split_part(contenido, ',', 1)),
    btrim(split_part(contenido, ',', 2)),
    btrim(split_part(contenido, ',', 3)),
    btrim(split_part(contenido, ',', 4)),
    btrim(split_part(contenido, ',', 5)),
    btrim(split_part(contenido, ',', 6))
FROM stg_libros_raw;

UPDATE stg_libros
SET motivo = CASE
    WHEN cantidad_campos IS DISTINCT FROM 6
        THEN 'tiene ' || COALESCE(cantidad_campos, 0) || ' columnas, se esperaban 6'
    WHEN isbn = ''
        THEN 'isbn vacío'
    WHEN isbn !~ '^[0-9]{13}$'
        THEN 'isbn no tiene 13 dígitos'
    WHEN titulo = ''
        THEN 'título vacío'
    WHEN char_length(titulo) > 200
        THEN 'título supera 200 caracteres'
    WHEN autor = ''
        THEN 'autor vacío'
    WHEN char_length(autor) > 150
        THEN 'autor supera 150 caracteres'
    WHEN categoria = ''
        THEN 'categoría vacía'
    WHEN char_length(categoria) > 100
        THEN 'categoría supera 100 caracteres'
    WHEN anio !~ '^[0-9]{1,4}$'
        THEN 'año no numérico'
    WHEN anio::INTEGER NOT BETWEEN 1400 AND 2100
        THEN 'año fuera de rango'
    WHEN ejemplares ~ '^-[0-9]+$'
        THEN 'ejemplares negativo'
    WHEN ejemplares !~ '^[0-9]+$'
        THEN 'ejemplares no numérico'
    WHEN length(ejemplares) > 9
        THEN 'ejemplares demasiado grande'
    WHEN EXISTS (
        SELECT 1
        FROM biblioteca.libro l
        WHERE l."isbn" = stg_libros.isbn
    )
        THEN 'isbn ya existe en el catálogo'
    ELSE NULL
END;

UPDATE stg_libros s
SET motivo = 'isbn repetido en el archivo'
WHERE s.motivo IS NULL
  AND EXISTS (
      SELECT 1
      FROM stg_libros anterior
      WHERE anterior.isbn = s.isbn
        AND anterior.linea < s.linea
        AND anterior.motivo IS NULL
  );

INSERT INTO biblioteca.libro (
    "isbn",
    "titulo",
    "autor",
    "categoria",
    "anio_publicacion",
    "ejemplares_disponibles"
)
SELECT
    isbn,
    titulo,
    autor,
    categoria,
    anio::INTEGER,
    ejemplares::INTEGER
FROM stg_libros
WHERE motivo IS NULL;

INSERT INTO biblioteca.ejemplares ("FK_id_libro")
SELECT
    l."PK_id_libro"
FROM stg_libros s
JOIN biblioteca.libro l
  ON l."isbn" = s.isbn
CROSS JOIN LATERAL generate_series(1, s.ejemplares::INTEGER)
WHERE s.motivo IS NULL;

INSERT INTO rechazo_carga (
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
FROM stg_libros
WHERE motivo IS NOT NULL;

COMMIT;

SELECT count(*) FILTER (WHERE motivo IS NULL)     AS cargadas,
       count(*) FILTER (WHERE motivo IS NOT NULL) AS rechazadas
FROM stg_libros;

SELECT linea, motivo, contenido
FROM stg_libros
WHERE motivo IS NOT NULL
ORDER BY linea;
