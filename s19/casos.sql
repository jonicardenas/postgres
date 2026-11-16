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

-- CASO 2:

--Punto A: Evidencia SQL de los problemas del esquema original

--Problema principal (incumple 1FN — Primera Forma Normal): 
--Tiene grupos repetidos mediante columnas numeradas 
--(medicamento1, dosis1, medicamento2, dosis2, medicamento3, dosis3). 

--Problema secundario (incumple 3FN — Tercera Forma Normal): por una dependencia 
--transitiva con los datos del paciente:
--num_formula -> doc_paciente (cada fórmula pertenece a un paciente).
--doc_paciente -> nombre_paciente (el documento determina el nombre del paciente).
--Por transitividad, nombre_paciente depende de num_formula a través de 
--un atributo no clave (doc_paciente).

--Dependencia del detalle: Una vez separados los medicamentos en filas, se cumple 
--(num_formula, medicamento) -> dosis

--Evidencia SQL y punto B:
SET search_path TO farmacia;

-- Evidencia del problema principal (1FN): grupos repetidos, columnas en NULL
SELECT num_formula,
       (medicamento1 IS NOT NULL)::int +
       (medicamento2 IS NOT NULL)::int +
       (medicamento3 IS NOT NULL)::int AS cant_medicamentos,
       medicamento1, medicamento2, medicamento3
FROM formula;

SELECT count(*) AS formulas_con_acetaminofen
FROM formula
WHERE medicamento1 ILIKE '%acetaminofén%'
   OR medicamento2 ILIKE '%acetaminofén%'
   OR medicamento3 ILIKE '%acetaminofén%';

-- Evidencia del problema secundario (3FN): datos del paciente repetidos
-- Dependencia funcional doc_paciente -> nombre_paciente.
SELECT doc_paciente, nombre_paciente, count(*) AS total_formulas
FROM formula
GROUP BY doc_paciente, nombre_paciente
HAVING count(*) > 1;

SELECT doc_paciente
FROM formula
GROUP BY doc_paciente
HAVING count(DISTINCT nombre_paciente) > 1;

--Esquema corregido (cumple 1FN y 3FN) y punto C:
--paciente (doc_paciente PK, nombre_paciente NOT NULL)
--formula (num_formula PK, fecha NOT NULL, doc_paciente FK -> paciente)
--detalle_formula (num_formula PK/FK -> formula, medicamento PK, dosis NOT NULL)

--Migración de datos a esquema corregido (punto D):

SET search_path TO farmacia;

BEGIN;

-- Crear las tablas nuevas con sus restricciones
CREATE TABLE paciente (
    doc_paciente     varchar(15) PRIMARY KEY,
    nombre_paciente  varchar(80) NOT NULL
);

CREATE TABLE detalle_formula (
    num_formula  integer     NOT NULL REFERENCES formula(num_formula),
    medicamento  varchar(60) NOT NULL,
    dosis        varchar(40) NOT NULL,
    PRIMARY KEY (num_formula, medicamento)
);

-- Migrar pacientes únicos
INSERT INTO paciente (doc_paciente, nombre_paciente)
SELECT DISTINCT doc_paciente, nombre_paciente
FROM formula;

-- Migrar medicamentos de columnas numeradas a filas usando UNION ALL
INSERT INTO detalle_formula (num_formula, medicamento, dosis)
SELECT num_formula, medicamento1, dosis1
FROM formula
WHERE medicamento1 IS NOT NULL
UNION ALL
SELECT num_formula, medicamento2, dosis2
FROM formula
WHERE medicamento2 IS NOT NULL
UNION ALL
SELECT num_formula, medicamento3, dosis3
FROM formula
WHERE medicamento3 IS NOT NULL;

-- Verificar integridad en ambos sentidos antes de borrar columnas viejas.
WITH datos_originales AS (
    SELECT num_formula, fecha, doc_paciente, nombre_paciente, medicamento1 AS medicamento, dosis1 AS dosis
    FROM formula
    WHERE medicamento1 IS NOT NULL
    UNION ALL
    SELECT num_formula, fecha, doc_paciente, nombre_paciente, medicamento2, dosis2
    FROM formula
    WHERE medicamento2 IS NOT NULL
    UNION ALL
    SELECT num_formula, fecha, doc_paciente, nombre_paciente, medicamento3, dosis3
    FROM formula
    WHERE medicamento3 IS NOT NULL
),
datos_migrados AS (
    SELECT f.num_formula, f.fecha, p.doc_paciente, p.nombre_paciente, d.medicamento, d.dosis
    FROM formula f
    JOIN paciente p ON f.doc_paciente = p.doc_paciente
    JOIN detalle_formula d ON f.num_formula = d.num_formula
)
SELECT 'faltan en la migracion' AS diferencia, diferencias.*
FROM (
    SELECT * FROM datos_originales
    EXCEPT
    SELECT * FROM datos_migrados
) AS diferencias
UNION ALL
SELECT 'sobran en la migracion' AS diferencia, diferencias.*
FROM (
    SELECT * FROM datos_migrados
    EXCEPT
    SELECT * FROM datos_originales
) AS diferencias;

-- Agregar la FK en formula y eliminar las columnas redundantes 
ALTER TABLE formula
    ADD CONSTRAINT fk_formula_paciente FOREIGN KEY (doc_paciente) REFERENCES paciente(doc_paciente),
    DROP COLUMN nombre_paciente,
    DROP COLUMN medicamento1,
    DROP COLUMN dosis1,
    DROP COLUMN medicamento2,
    DROP COLUMN dosis2,
    DROP COLUMN medicamento3,
    DROP COLUMN dosis3;

COMMIT;

--Solucion a la queja de la evidencia SQL (punto E):

SET search_path TO farmacia;

-- Conteos esperados con los datos iniciales: 3 pacientes, 4 fórmulas,
--    8 medicamentos recetados y 5 medicamentos distintos.
SELECT 'paciente' AS tabla, count(*) AS filas FROM paciente
UNION ALL
SELECT 'formula', count(*) FROM formula
UNION ALL
SELECT 'detalle_formula', count(*) FROM detalle_formula
UNION ALL
SELECT 'medicamentos_distintos', count(DISTINCT medicamento) FROM detalle_formula;

-- Queja 1 resuelta: consultar fórmulas con acetaminofén en una sola columna
SELECT count(DISTINCT num_formula) AS formulas_con_acetaminofen
FROM detalle_formula
WHERE medicamento ILIKE 'Acetaminofén%';

-- Queja 2 resuelta: demostrar que cabe un cuarto medicamento sin dejar
-- datos de prueba en la base.
BEGIN;

INSERT INTO detalle_formula (num_formula, medicamento, dosis)
VALUES (703, 'Naproxeno 250 mg', 'cada 12 h');

SELECT * FROM detalle_formula WHERE num_formula = 703;

ROLLBACK;

--Pregunta propia
--¿Por qué no basta con agregar medicamento4 y dosis4?
--1. El límite seguiría siendo arbitrario: si una fórmula tuviera cinco
--medicamentos, habría que volver a modificar la tabla y la aplicación.
--2. Para buscar o contar un medicamento habría que consultar cada columna
--numerada; con detalle_formula basta buscar en una sola columna.
--3. Muchas fórmulas tienen menos medicamentos que columnas disponibles, por
--lo que los pares adicionales quedarían en NULL y harían más dispersos los datos.

-- Caso 3:
SET search_path TO cursos_libres;

-- Dependencias funcionales:
--   doc_participante -> nombre_participante, correo
--   correo -> doc_participante
--   cod_curso -> nombre_curso, cod_sede
--   cod_sede -> direccion_sede
--   (doc_participante, cod_curso) -> valor_pagado
-- Claves candidatas: (doc_participante, cod_curso) y (correo, cod_curso).
--   El id serial es solo una clave sustituta.
-- Problema principal: falta UNIQUE (doc_participante, cod_curso).
--   Las filas 3 y 7 son la misma inscripción de Juliana Rey en C20 y se suma dos veces.
-- Problemas secundarios:
--   2FN: datos del participante dependen solo de doc_participante y datos del
--     curso solo de cod_curso.
--   3FN: cod_curso -> cod_sede -> direccion_sede.
--   correo sin UNIQUE aunque identifica al participante.

-- Evidencia: 
-- La queja: C20 suma 580000 y debería sumar 380000
SELECT cod_curso, nombre_curso, sum(valor_pagado)
FROM inscripcion GROUP BY cod_curso, nombre_curso;

-- Inscripciones duplicadas:
SELECT doc_participante, cod_curso, count(*)
FROM inscripcion GROUP BY doc_participante, cod_curso HAVING count(*) > 1;

-- Redundancia de la dirección:
SELECT direccion_sede, count(*) FROM inscripcion
GROUP BY direccion_sede ORDER BY count(*) DESC;

-- Los datos no contradicen las dependencias (todas deben dar 0 filas):
SELECT doc_participante FROM inscripcion GROUP BY doc_participante
  HAVING count(DISTINCT nombre_participante) > 1 OR count(DISTINCT correo) > 1;
SELECT correo FROM inscripcion GROUP BY correo HAVING count(DISTINCT doc_participante) > 1;
SELECT cod_curso FROM inscripcion GROUP BY cod_curso
  HAVING count(DISTINCT nombre_curso) > 1 OR count(DISTINCT cod_sede) > 1;
SELECT cod_sede FROM inscripcion GROUP BY cod_sede HAVING count(DISTINCT direccion_sede) > 1;

-- Se elimina la fila 7 porque es idéntica a la 3 en todos los campos
-- y las reglas dicen que un participante se inscribe a lo sumo una vez por curso.

-- El esquema corregido: 
--   participante (doc_participante PK, nombre_participante, correo UNIQUE NOT NULL)
--   sede         (cod_sede PK, direccion_sede)
--   curso        (cod_curso PK, nombre_curso, cod_sede FK -> sede)
--   inscripcion  (doc_participante FK, cod_curso FK, valor_pagado,
--                 PK (doc_participante, cod_curso))
-- valor_pagado depende de la clave completa (el descuento es por inscripción).

-- Migración: 
-- Conteos esperados (calculados antes): 4 participantes, 2 sedes,
-- 3 cursos, 7 inscripciones (8 menos el duplicado).

BEGIN;

CREATE TABLE sede (
  cod_sede char(2) PRIMARY KEY,
  direccion_sede varchar(60) NOT NULL);
CREATE TABLE curso (
  cod_curso char(3) PRIMARY KEY,
  nombre_curso varchar(60) NOT NULL,
  cod_sede char(2) NOT NULL REFERENCES sede);
CREATE TABLE participante (
  doc_participante varchar(15) PRIMARY KEY,
  nombre_participante varchar(80) NOT NULL,
  correo varchar(120) NOT NULL UNIQUE);
CREATE TABLE inscripcion_nueva (
  doc_participante varchar(15) REFERENCES participante,
  cod_curso char(3) REFERENCES curso,
  valor_pagado integer NOT NULL CHECK (valor_pagado >= 0),
  PRIMARY KEY (doc_participante, cod_curso));

INSERT INTO sede SELECT DISTINCT cod_sede, direccion_sede FROM inscripcion;
INSERT INTO curso SELECT DISTINCT cod_curso, nombre_curso, cod_sede FROM inscripcion;
INSERT INTO participante SELECT DISTINCT doc_participante, nombre_participante, correo FROM inscripcion;
INSERT INTO inscripcion_nueva SELECT DISTINCT doc_participante, cod_curso, valor_pagado FROM inscripcion;

-- Verificación:
-- Esperado: 4, 2, 3, 7
SELECT (SELECT count(*) FROM participante) AS participantes,
       (SELECT count(*) FROM sede) AS sedes,
       (SELECT count(*) FROM curso) AS cursos,
       (SELECT count(*) FROM inscripcion_nueva) AS inscripciones;

-- Ambas deben dar 0 filas:
(SELECT DISTINCT doc_participante, nombre_participante, correo, cod_curso,
        nombre_curso, cod_sede, direccion_sede, valor_pagado FROM inscripcion)
EXCEPT
(SELECT p.doc_participante, p.nombre_participante, p.correo, c.cod_curso,
        c.nombre_curso, s.cod_sede, s.direccion_sede, i.valor_pagado
 FROM inscripcion_nueva i
 JOIN participante p USING (doc_participante)
 JOIN curso c USING (cod_curso)
 JOIN sede s USING (cod_sede));

(SELECT p.doc_participante, p.nombre_participante, p.correo, c.cod_curso,
        c.nombre_curso, s.cod_sede, s.direccion_sede, i.valor_pagado
 FROM inscripcion_nueva i
 JOIN participante p USING (doc_participante)
 JOIN curso c USING (cod_curso)
 JOIN sede s USING (cod_sede))
EXCEPT
(SELECT DISTINCT doc_participante, nombre_participante, correo, cod_curso,
        nombre_curso, cod_sede, direccion_sede, valor_pagado FROM inscripcion);

DROP TABLE inscripcion;
ALTER TABLE inscripcion_nueva RENAME TO inscripcion;

-- La queja resuelta: Fotografía digital debe dar 380000
SELECT c.nombre_curso, sum(i.valor_pagado)
FROM inscripcion i JOIN curso c USING (cod_curso)
GROUP BY c.nombre_curso;

COMMIT;

-- PREGUNTA PROPIA
-- ¿Por qué una PK de una columna no la pone en 2FN?
--   Las formas normales se evalúan sobre TODAS las claves candidatas.
--   (doc_participante, cod_curso) identifica una inscripción aunque nadie la
--   declaró, y nombre_participante o nombre_curso dependen solo de una parte
--   de ella. Agregar un id no normaliza nada: solo cambia el nombre de la PK.
-- ¿Qué restricción faltaba?
--   UNIQUE (doc_participante, cod_curso): habría rechazado la segunda inscripción
--   de Juliana en Fotografía digital y el descuadre de 200000 no habría ocurrido.
--   También faltaba UNIQUE (correo).



-- Caso 4:

BEGIN;

ALTER TABLE envios.envio RENAME TO envio_original;


CREATE TABLE envios.zona (
    id_zona SMALLINT PRIMARY KEY
);


CREATE TABLE envios.ciudad (
    ciudad_destino VARCHAR(40) PRIMARY KEY,
    departamento VARCHAR(40) NOT NULL,
    id_zona SMALLINT NOT NULL
        REFERENCES envios.zona(id_zona)
);


CREATE TABLE envios.tarifa_zona (
    id_tarifa INTEGER PRIMARY KEY,
    id_zona SMALLINT NOT NULL
        REFERENCES envios.zona(id_zona),
    tarifa_kg INTEGER NOT NULL CHECK (tarifa_kg > 0),
    vigente_desde DATE NOT NULL,
    vigente_hasta DATE,
    CHECK (
        vigente_hasta IS NULL
        OR vigente_hasta >= vigente_desde
    )
);


CREATE TABLE envios.envio (
    num_guia CHAR(3) PRIMARY KEY,
    fecha DATE NOT NULL,
    ciudad_destino VARCHAR(40) NOT NULL
        REFERENCES envios.ciudad(ciudad_destino),
    id_tarifa INTEGER NOT NULL
        REFERENCES envios.tarifa_zona(id_tarifa),
    peso_kg NUMERIC(5,1) NOT NULL CHECK (peso_kg > 0),
    valor_facturado INTEGER NOT NULL
        CHECK (valor_facturado >= 0)
);


INSERT INTO envios.zona (id_zona)
SELECT DISTINCT zona
FROM envios.envio_original
ORDER BY zona;


INSERT INTO envios.ciudad (
    ciudad_destino,
    departamento,
    id_zona
)
SELECT DISTINCT
    ciudad_destino,
    departamento,
    zona
FROM envios.envio_original
ORDER BY ciudad_destino;


INSERT INTO envios.tarifa_zona (
    id_tarifa,
    id_zona,
    tarifa_kg,
    vigente_desde,
    vigente_hasta
)
SELECT
    zona,
    zona,
    MIN(tarifa_kg),
    MIN(fecha),
    NULL
FROM envios.envio_original
GROUP BY zona
ORDER BY zona;


INSERT INTO envios.envio (
    num_guia,
    fecha,
    ciudad_destino,
    id_tarifa,
    peso_kg,
    valor_facturado
)
SELECT
    o.num_guia,
    o.fecha,
    o.ciudad_destino,
    t.id_tarifa,
    o.peso_kg,
    o.valor
FROM envios.envio_original o
JOIN envios.ciudad c
    ON c.ciudad_destino = o.ciudad_destino
   AND c.id_zona = o.zona
JOIN envios.tarifa_zona t
    ON t.id_zona = c.id_zona
   AND t.tarifa_kg = o.tarifa_kg
   AND o.fecha >= t.vigente_desde
   AND (
       t.vigente_hasta IS NULL
       OR o.fecha <= t.vigente_hasta
   );


CREATE VIEW envios.validacion_tarifas AS
SELECT
    e.num_guia,
    e.fecha,
    e.ciudad_destino,
    c.id_zona AS zona_ciudad,
    e.id_tarifa,
    t.id_zona AS zona_tarifa,
    t.tarifa_kg,
    CASE
        WHEN c.id_zona <> t.id_zona
            THEN 'Zona incorrecta'
        WHEN e.fecha < t.vigente_desde
            OR (
                t.vigente_hasta IS NOT NULL
                AND e.fecha > t.vigente_hasta
            )
            THEN 'Tarifa fuera de vigencia'
        ELSE 'Correcto'
    END AS estado_validacion
FROM envios.envio e
JOIN envios.ciudad c
    ON c.ciudad_destino = e.ciudad_destino
JOIN envios.tarifa_zona t
    ON t.id_tarifa = e.id_tarifa;


CREATE VIEW envios.detalle_envio AS
SELECT
    e.num_guia,
    e.fecha,
    e.ciudad_destino,
    c.departamento,
    c.id_zona,
    t.tarifa_kg,
    e.peso_kg,
    e.valor_facturado,
    e.peso_kg * t.tarifa_kg AS valor_calculado,
    e.valor_facturado - (e.peso_kg * t.tarifa_kg)
        AS diferencia
FROM envios.envio e
JOIN envios.ciudad c
    ON c.ciudad_destino = e.ciudad_destino
JOIN envios.tarifa_zona t
    ON t.id_tarifa = e.id_tarifa;


SELECT
    (SELECT COUNT(*) FROM envios.envio_original) AS registros_originales,
    (SELECT COUNT(*) FROM envios.envio) AS registros_migrados;

COMMIT;

-- RESPUESTA A LA PREGUNTA PROPIA
--
-- Si la transportadora aumenta las tarifas en enero, no se
-- debe modificar la tarifa historica utilizada por los envios
-- realizados en octubre.
--
-- Para evitar que el cambio afecte los valores anteriores,
-- se deben registrar nuevas tarifas con su respectivo periodo
-- de vigencia, en lugar de sobrescribir las tarifas anteriores.
--
-- Cada envio conserva la referencia a la tarifa que le
-- correspondia en la fecha en que fue realizado.
--
-- Esto permite consultar y calcular los valores historicos
-- sin que los aumentos posteriores alteren los registros.
--
-- La conservacion de la tarifa historica no constituye una
-- redundancia innecesaria, sino el almacenamiento de
-- informacion necesaria para mantener la historia de los
-- valores aplicados a cada envio.

