-- CASO 1
SET search_path TO gimnasio;

SELECT * FROM socio 
WHERE clases LIKE ('%Yoga%');


SELECT * FROM socio 
WHERE clases LIKE ('%Spinning%');

SELECT nombre, initcap(TRIM(clase)) AS clase 
FROM socio s, string_to_table(s.clases, ';') AS clase;


CREATE TABLE plan (
    tipo       varchar(20) PRIMARY KEY,
    valor_plan integer     NOT NULL
);

CREATE TABLE clase (
    id_clase SERIAL      PRIMARY KEY,
    clase    varchar(50) UNIQUE NOT NULL
);

CREATE TABLE socio_nuevo (
    id_socio integer     PRIMARY KEY,
    nombre   varchar(80) NOT NULL,
    plan     varchar(20) NOT NULL REFERENCES plan(tipo)
);

CREATE TABLE clases_socio (
    id_socio integer REFERENCES socio_nuevo(id_socio),
    id_clase integer REFERENCES clase(id_clase),
    PRIMARY KEY (id_socio, id_clase)
);

-- Migracion

INSERT INTO plan (tipo, valor_plan)
SELECT DISTINCT plan, valor_plan 
FROM socio;

INSERT INTO clase (clase)
SELECT DISTINCT initcap(TRIM(c))
FROM socio s, string_to_table(s.clases, ';') AS c;

INSERT INTO socio_nuevo (id_socio, nombre, plan)
SELECT id_socio, nombre, plan 
FROM socio;

-- Llena tabla clases_socio (cruzando el texto limpio con la tabla clase para obtener id_clase)
INSERT INTO clases_socio (id_socio, id_clase)
SELECT DISTINCT s.id_socio, c.id_clase
FROM socio s, string_to_table(s.clases, ';') AS pedazo
JOIN clase c ON c.clase = initcap(TRIM(pedazo));

-- Con esta estructura exacta, el horario (dia y hora) iría en la tabla clase 
-- (si cada id_clase tiene un único horario fijo) o en una tabla horario_clase(id_clase, dia, hora) 
-- que referencie a clase(id_clase) (si una misma clase como Yoga se dicta varios días a la semana). 
-- En el diseño original era imposible porque clase no existía como entidad independiente, 
-- sino que estaba mezclada como texto libre dentro de la fila de cada socio.