
\set ON_ERROR_STOP on

\if :{?archivo}
\else
  \set archivo /scripts/datos/libros_semilla.csv
\endif

DROP TABLE IF EXISTS pg_temp.stg_libros_raw;
CREATE TEMP TABLE stg_libros_raw (
    linea BIGINT GENERATED ALWAYS AS IDENTITY,
    contenido TEXT NOT NULL
);

DROP TABLE IF EXISTS pg_temp.stg_libros;
CREATE TEMP TABLE stg_libros (
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
    WHEN cantidad_campos <> 6
        THEN 'Cantidad de campos distinta de 6'
    WHEN isbn !~ '^[0-9]{13}$'
        THEN 'ISBN debe contener exactamente 13 dígitos'
    WHEN titulo = ''
        THEN 'Título obligatorio'
    WHEN char_length(titulo) > 200
        THEN 'Título supera 200 caracteres'
    WHEN autor = ''
        THEN 'Autor obligatorio'
    WHEN char_length(autor) > 150
        THEN 'Autor supera 150 caracteres'
    WHEN categoria = ''
        THEN 'Categoría obligatoria según las reglas de carga'
    WHEN char_length(categoria) > 100
        THEN 'Categoría supera 100 caracteres'
    WHEN anio !~ '^[0-9]{1,4}$'
        THEN 'Año de publicación no numérico o vacío'
    WHEN anio::INTEGER NOT BETWEEN 1400 AND 2100
        THEN 'Año de publicación fuera del rango 1400-2100'
    WHEN ejemplares !~ '^[0-9]+$'
        THEN 'Ejemplares disponibles debe ser un entero no negativo'
    WHEN length(ejemplares) > 9
        THEN 'Cantidad de ejemplares demasiado grande'
    WHEN isbn IN (
        SELECT l."isbn"
        FROM biblioteca.libro l
    )
        THEN 'ISBN ya existe en la tabla Libro'
    ELSE NULL
END;

UPDATE stg_libros s
SET motivo = 'ISBN duplicado dentro del archivo'
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
FROM stg_libros
WHERE motivo IS NOT NULL;

COMMIT;

SELECT 'Libros cargados' AS resultado, COUNT(*) AS cantidad
FROM stg_libros
WHERE motivo IS NULL;

SELECT 'Filas rechazadas' AS resultado, COUNT(*) AS cantidad
FROM stg_libros
WHERE motivo IS NOT NULL;

SELECT motivo, COUNT(*) AS cantidad
FROM stg_libros
WHERE motivo IS NOT NULL
GROUP BY motivo
ORDER BY motivo;
