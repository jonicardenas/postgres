-- ============================================================
-- S18 - TALLER DE NORMALIZACION
-- Parte B: descomposicion de servicio_plano hasta 3FN
-- Base de datos: curso
-- Esquema: automotriz
-- ============================================================

-- IMPORTANTE:
-- Este archivo documenta el desarrollo de la parte B.
-- Debe ejecutarse despues de crear y cargar servicio_plano
-- mediante scripts/S18-automotriz.sql.
--
-- No ejecutar nuevamente S18-automotriz.sql despues de crear
-- las tablas normalizadas, porque elimina el esquema automotriz.

-- ============================================================
-- B(a). DETECCION Y CORRECCION DE CONTRADICCIONES
-- ============================================================

-- Se revisaron las siguientes dependencias funcionales:
--
-- 1. num_orden -> fecha_ingreso, kilometraje, placa
-- 2. placa -> modelo, cedula_dueno
-- 3. modelo -> marca
-- 4. cedula_dueno -> nombre_dueno, telefono_dueno
-- 5. cod_servicio -> nombre_servicio, precio_lista
-- 6. cod_mecanico -> nombre_mecanico
-- 7. (num_orden, cod_servicio) -> precio_cobrado, cod_mecanico
--
-- Las consultas de agrupacion y COUNT(DISTINCT ...) detectaron
-- una contradiccion en la dependencia numero 4.
--
-- La cedula 16700002 tenia dos telefonos:
-- 3104445566 y 3104445567.
--
-- Se inspeccionaron los registros y se decidio conservar
-- 3104445566, porque aparecia en mas ordenes y registros.

-- Consultas para detectar contradicciones en las siete DF.
-- Cada consulta debe devolver cero filas si la DF se cumple.

-- 1. num_orden -> fecha_ingreso, kilometraje, placa
SELECT num_orden
FROM automotriz.servicio_plano
GROUP BY num_orden
HAVING COUNT(DISTINCT (fecha_ingreso, kilometraje, placa)) > 1;

-- 2. placa -> modelo, cedula_dueno
SELECT placa
FROM automotriz.servicio_plano
GROUP BY placa
HAVING COUNT(DISTINCT (modelo, cedula_dueno)) > 1;

-- 3. modelo -> marca
SELECT modelo
FROM automotriz.servicio_plano
GROUP BY modelo
HAVING COUNT(DISTINCT marca) > 1;

-- 4. cedula_dueno -> nombre_dueno, telefono_dueno
SELECT cedula_dueno
FROM automotriz.servicio_plano
GROUP BY cedula_dueno
HAVING COUNT(DISTINCT (nombre_dueno, telefono_dueno)) > 1;

-- 5. cod_servicio -> nombre_servicio, precio_lista
SELECT cod_servicio
FROM automotriz.servicio_plano
GROUP BY cod_servicio
HAVING COUNT(DISTINCT (nombre_servicio, precio_lista)) > 1;

-- 6. cod_mecanico -> nombre_mecanico
SELECT cod_mecanico
FROM automotriz.servicio_plano
GROUP BY cod_mecanico
HAVING COUNT(DISTINCT nombre_mecanico) > 1;

-- 7. (num_orden, cod_servicio) -> precio_cobrado, cod_mecanico
SELECT num_orden, cod_servicio
FROM automotriz.servicio_plano
GROUP BY num_orden, cod_servicio
HAVING COUNT(DISTINCT (precio_cobrado, cod_mecanico)) > 1;

UPDATE automotriz.servicio_plano
SET telefono_dueno = '3104445566'
WHERE cedula_dueno = '16700002'
  AND telefono_dueno = '3104445567';

-- Resultado esperado: UPDATE 1.
--
-- Despues de la correccion, las siete dependencias funcionales
-- no presentaron contradicciones en los datos.

-- ============================================================
-- B(b). CREACION DE LAS TABLAS NORMALIZADAS
-- ============================================================

-- Tabla de propietarios
CREATE TABLE automotriz.dueno (
    cedula_dueno   varchar(15) PRIMARY KEY,
    nombre_dueno   varchar(80) NOT NULL,
    telefono_dueno varchar(15) NOT NULL
);

-- Tabla de marcas asociadas a modelos
CREATE TABLE automotriz.modelo_vehiculo (
    modelo varchar(30) PRIMARY KEY,
    marca  varchar(30) NOT NULL
);

-- Tabla de mecanicos
CREATE TABLE automotriz.mecanico (
    cod_mecanico    char(3) PRIMARY KEY,
    nombre_mecanico varchar(80) NOT NULL
);

-- Tabla de vehiculos
CREATE TABLE automotriz.vehiculo (
    placa        char(6) PRIMARY KEY,
    modelo       varchar(30) NOT NULL
                 REFERENCES automotriz.modelo_vehiculo(modelo),
    cedula_dueno varchar(15) NOT NULL
                 REFERENCES automotriz.dueno(cedula_dueno)
);

-- Catalogo de servicios
CREATE TABLE automotriz.servicio (
    cod_servicio    char(3) PRIMARY KEY,
    nombre_servicio varchar(60) NOT NULL,
    precio_lista    integer NOT NULL
);

-- Tabla de ordenes de trabajo
CREATE TABLE automotriz.orden (
    num_orden     integer PRIMARY KEY,
    fecha_ingreso date NOT NULL,
    kilometraje   integer NOT NULL,
    placa         char(6) NOT NULL
                  REFERENCES automotriz.vehiculo(placa)
);

-- Detalle de servicios realizados en cada orden
CREATE TABLE automotriz.detalle_orden (
    num_orden      integer NOT NULL
                   REFERENCES automotriz.orden(num_orden),
    cod_servicio   char(3) NOT NULL
                   REFERENCES automotriz.servicio(cod_servicio),
    precio_cobrado integer NOT NULL,
    cod_mecanico   char(3) NOT NULL
                   REFERENCES automotriz.mecanico(cod_mecanico),
    PRIMARY KEY (num_orden, cod_servicio)
);

-- Resultado: siete tablas creadas con sus claves primarias,
-- claves foraneas y restricciones NOT NULL.

-- ============================================================
-- B(c). POBLACION DE LAS TABLAS NORMALIZADAS
-- ============================================================

-- Primero se insertan las tablas independientes.
INSERT INTO automotriz.dueno (
    cedula_dueno, nombre_dueno, telefono_dueno
)
SELECT DISTINCT
    cedula_dueno, nombre_dueno, telefono_dueno
FROM automotriz.servicio_plano;

INSERT INTO automotriz.modelo_vehiculo (
    modelo, marca
)
SELECT DISTINCT
    modelo, marca
FROM automotriz.servicio_plano;

INSERT INTO automotriz.mecanico (
    cod_mecanico, nombre_mecanico
)
SELECT DISTINCT
    cod_mecanico, nombre_mecanico
FROM automotriz.servicio_plano;

-- Luego se insertan las tablas que dependen de las anteriores.
INSERT INTO automotriz.vehiculo (
    placa, modelo, cedula_dueno
)
SELECT DISTINCT
    placa, modelo, cedula_dueno
FROM automotriz.servicio_plano;

INSERT INTO automotriz.servicio (
    cod_servicio, nombre_servicio, precio_lista
)
SELECT DISTINCT
    cod_servicio, nombre_servicio, precio_lista
FROM automotriz.servicio_plano;

INSERT INTO automotriz.orden (
    num_orden, fecha_ingreso, kilometraje, placa
)
SELECT DISTINCT
    num_orden, fecha_ingreso, kilometraje, placa
FROM automotriz.servicio_plano;

-- Finalmente se insertan los detalles de las ordenes.
INSERT INTO automotriz.detalle_orden (
    num_orden, cod_servicio, precio_cobrado, cod_mecanico
)
SELECT DISTINCT
    num_orden, cod_servicio, precio_cobrado, cod_mecanico
FROM automotriz.servicio_plano;

-- Verificacion de cantidades cargadas.
SELECT 'servicio_plano' AS tabla, COUNT(*) AS registros
FROM automotriz.servicio_plano
UNION ALL
SELECT 'dueno', COUNT(*) FROM automotriz.dueno
UNION ALL
SELECT 'modelo_vehiculo', COUNT(*) FROM automotriz.modelo_vehiculo
UNION ALL
SELECT 'mecanico', COUNT(*) FROM automotriz.mecanico
UNION ALL
SELECT 'vehiculo', COUNT(*) FROM automotriz.vehiculo
UNION ALL
SELECT 'servicio', COUNT(*) FROM automotriz.servicio
UNION ALL
SELECT 'orden', COUNT(*) FROM automotriz.orden
UNION ALL
SELECT 'detalle_orden', COUNT(*) FROM automotriz.detalle_orden;

-- Conteos esperados en la carga inicial:
-- servicio_plano: 11
-- dueno: 3
-- modelo_vehiculo: 4
-- mecanico: 3
-- vehiculo: 4
-- servicio: 5
-- orden: 6
-- detalle_orden: 11

-- ============================================================
-- B(d). RECONSTRUCCION Y VERIFICACION SIN PERDIDA DE INFORMACION
-- ============================================================

-- Se reconstruye la planilla original mediante JOIN.
CREATE OR REPLACE VIEW automotriz.reconstruida AS
SELECT
    o.num_orden,
    o.fecha_ingreso,
    o.kilometraje,
    v.placa,
    v.modelo,
    mv.marca,
    d.cedula_dueno,
    d.nombre_dueno,
    d.telefono_dueno,
    s.cod_servicio,
    s.nombre_servicio,
    s.precio_lista,
    det.precio_cobrado,
    m.cod_mecanico,
    m.nombre_mecanico
FROM automotriz.detalle_orden det
JOIN automotriz.orden o
    ON o.num_orden = det.num_orden
JOIN automotriz.vehiculo v
    ON v.placa = o.placa
JOIN automotriz.modelo_vehiculo mv
    ON mv.modelo = v.modelo
JOIN automotriz.dueno d
    ON d.cedula_dueno = v.cedula_dueno
JOIN automotriz.servicio s
    ON s.cod_servicio = det.cod_servicio
JOIN automotriz.mecanico m
    ON m.cod_mecanico = det.cod_mecanico;

-- Comparacion de cantidades de filas.
SELECT 'servicio_plano' AS tabla, COUNT(*) AS registros
FROM automotriz.servicio_plano
UNION ALL
SELECT 'reconstruida', COUNT(*)
FROM automotriz.reconstruida;

-- Filas que existen en la original pero no en la reconstruida.
SELECT *
FROM automotriz.servicio_plano
EXCEPT
SELECT *
FROM automotriz.reconstruida;

-- Filas que existen en la reconstruida pero no en la original.
SELECT *
FROM automotriz.reconstruida
EXCEPT
SELECT *
FROM automotriz.servicio_plano;

-- Verificacion resumida de diferencias en ambos sentidos.
SELECT 'original_menos_reconstruida' AS comparacion,
       COUNT(*) AS diferencias
FROM (
    SELECT * FROM automotriz.servicio_plano
    EXCEPT
    SELECT * FROM automotriz.reconstruida
) AS a
UNION ALL
SELECT 'reconstruida_menos_original',
       COUNT(*)
FROM (
    SELECT * FROM automotriz.reconstruida
    EXCEPT
    SELECT * FROM automotriz.servicio_plano
) AS b;

-- Resultado esperado antes de B(e):
-- servicio_plano: 11 filas
-- reconstruida: 11 filas
-- original_menos_reconstruida: 0
-- reconstruida_menos_original: 0

-- ============================================================
-- B(e). DEMOSTRACION DE LA ELIMINACION DE ANOMALIAS
-- ============================================================
--
-- IMPORTANTE:
-- Este apartado se ejecuta despues de B(d), porque modifica
-- los datos de las tablas normalizadas.
--
-- 1. ANOMALIA DE ACTUALIZACION:
-- Cambiar el telefono de un propietario en un solo registro.

UPDATE automotriz.dueno
SET telefono_dueno = '3105556677'
WHERE cedula_dueno = '16700002';

-- Verificar que el cambio se refleja en todas sus ordenes.
SELECT DISTINCT num_orden, cedula_dueno, telefono_dueno
FROM automotriz.reconstruida
WHERE cedula_dueno = '16700002'
ORDER BY num_orden;


-- 2. ANOMALIA DE INSERCION:
-- Registrar un mecanico que todavia no tiene servicios asignados.

INSERT INTO automotriz.mecanico (
    cod_mecanico, nombre_mecanico
)
VALUES ('M04', 'Carlos Mendoza');

-- Verificar que el mecanico existe y no tiene servicios.
SELECT m.cod_mecanico,
       m.nombre_mecanico,
       COUNT(det.cod_servicio) AS servicios_asignados
FROM automotriz.mecanico m
LEFT JOIN automotriz.detalle_orden det
    ON det.cod_mecanico = m.cod_mecanico
WHERE m.cod_mecanico = 'M04'
GROUP BY m.cod_mecanico, m.nombre_mecanico;


-- 3. ANOMALIA DE BORRADO:
-- Eliminar la orden 5002 sin perder el vehiculo ni los servicios
-- del catalogo.
--
-- La clave foranea de detalle_orden hacia orden utiliza
-- el comportamiento predeterminado NO ACTION. Por eso primero
-- se eliminan los detalles y despues la orden.

BEGIN;

DELETE FROM automotriz.detalle_orden
WHERE num_orden = 5002;

DELETE FROM automotriz.orden
WHERE num_orden = 5002;

COMMIT;

-- Verificar que la orden y sus detalles ya no existen,
-- pero el vehiculo y los servicios permanecen.

SELECT 'orden' AS elemento, COUNT(*) AS registros
FROM automotriz.orden
WHERE num_orden = 5002

UNION ALL

SELECT 'detalle_orden', COUNT(*)
FROM automotriz.detalle_orden
WHERE num_orden = 5002

UNION ALL

SELECT 'vehiculo', COUNT(*)
FROM automotriz.vehiculo
WHERE placa = 'DEF456'

UNION ALL

SELECT 'servicios_ACE_FRE', COUNT(*)
FROM automotriz.servicio
WHERE cod_servicio IN ('ACE', 'FRE');

-- Resultados esperados:
-- Telefono actualizado: 3105556677 en las ordenes del propietario.
-- Mecanico M04: 0 servicios asignados.
-- Orden 5002: 0 registros.
-- Detalles de orden 5002: 0 registros.
-- Vehiculo DEF456: 1 registro.
-- Servicios ACE y FRE: 2 registros.