-- S22. Parte A: reservas de salas de estudio.
-- Ejecutar despues de S22-reservas.sql, sobre la base curso.
-- Los errores de la bateria son intencionales; psql debe continuar con las
-- siguientes pruebas para poder ver todos los resultados.

\set ON_ERROR_STOP off

SET search_path TO reservas;

-- A1(a): las cuatro restricciones de la regla 1 y asistentes positivos.
ALTER TABLE reserva DROP CONSTRAINT IF EXISTS reserva_orden;
ALTER TABLE reserva
    ADD CONSTRAINT reserva_orden CHECK (fin > inicio);

ALTER TABLE reserva DROP CONSTRAINT IF EXISTS reserva_duracion;
ALTER TABLE reserva
    ADD CONSTRAINT reserva_duracion CHECK (fin - inicio <= INTERVAL '3 hours');

ALTER TABLE reserva DROP CONSTRAINT IF EXISTS reserva_horario;
ALTER TABLE reserva
    ADD CONSTRAINT reserva_horario CHECK (
        inicio::date = fin::date
        AND inicio::time >= TIME '07:00'
        AND fin::time <= TIME '21:00'
    );

ALTER TABLE reserva DROP CONSTRAINT IF EXISTS reserva_asistentes;
ALTER TABLE reserva
    ADD CONSTRAINT reserva_asistentes CHECK (asistentes > 0);

-- A1(b): los recursos dependen de la sala y se eliminan con ella.
-- Las reservas se conservan; no se permite borrar una sala o estudiante
-- que tenga reservas asociadas.
ALTER TABLE sala_recurso
    DROP CONSTRAINT IF EXISTS sala_recurso_id_sala_fkey;
ALTER TABLE sala_recurso
    ADD CONSTRAINT sala_recurso_id_sala_fkey
    FOREIGN KEY (id_sala) REFERENCES sala(id_sala) ON DELETE CASCADE;

ALTER TABLE reserva
    DROP CONSTRAINT IF EXISTS reserva_id_sala_fkey;
ALTER TABLE reserva
    ADD CONSTRAINT reserva_id_sala_fkey
    FOREIGN KEY (id_sala) REFERENCES sala(id_sala) ON DELETE RESTRICT;

ALTER TABLE reserva
    DROP CONSTRAINT IF EXISTS reserva_codigo_fkey;
ALTER TABLE reserva
    ADD CONSTRAINT reserva_codigo_fkey
    FOREIGN KEY (codigo) REFERENCES estudiante(codigo) ON DELETE RESTRICT;

-- A1(c): las cuatro inserciones deben fallar por su CHECK correspondiente.
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610006', dia(4) + TIME '10:00', dia(4) + TIME '09:00', 2);
-- Esperado: viola reserva_orden.

INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610006', dia(4) + TIME '08:00', dia(4) + TIME '12:00', 2);
-- Esperado: viola reserva_duracion.

INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610006', dia(4) + TIME '20:00', dia(4) + TIME '22:00', 2);
-- Esperado: viola reserva_horario.

INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610006', dia(4) + TIME '10:00', dia(4) + TIME '11:00', 0);
-- Esperado: viola reserva_asistentes.

BEGIN;
DELETE FROM sala WHERE id_sala = 4;
-- Esperado: se elimina la sala y sus recursos por ON DELETE CASCADE.
SELECT count(*) AS recursos_sala_4 FROM sala_recurso WHERE id_sala = 4;
-- Esperado: 0.
ROLLBACK;

DELETE FROM sala WHERE id_sala = 1;
-- Esperado: falla por ON DELETE RESTRICT; la sala tiene reservas.

BEGIN;
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (1, '2610006', dia(1) + TIME '09:00', dia(1) + TIME '10:00', 9);
-- Esperado: pasa los CHECK de A1; la capacidad y el cruce se analizan en A1(d).
ROLLBACK;

-- A1(d): el ultimo INSERT viola la regla 2 (9 asistentes exceden la
-- capacidad 4 de Sala A) y la regla 3 (se cruza con la reserva 1).
-- Un CHECK solo puede validar valores de la fila actual; no puede consultar
-- otras filas ni la capacidad de otra tabla. Estas reglas requieren lógica
-- que consulte los datos relacionados.

-- A2: funciones de apoyo para consultar horas semanales y disponibilidad.
CREATE OR REPLACE FUNCTION horas_semana(p_codigo varchar, p_dia date)
RETURNS numeric
LANGUAGE sql STABLE
AS $$
    SELECT ROUND(
        COALESCE(
            SUM(EXTRACT(EPOCH FROM (r.fin - r.inicio)) / 3600),
            0
        )::numeric,
        1
    )
    FROM reserva AS r
    WHERE r.codigo = p_codigo
      AND r.estado <> 'cancelada'
      AND r.inicio >= date_trunc('week', p_dia)
      AND r.inicio < date_trunc('week', p_dia) + INTERVAL '1 week';
$$;

CREATE OR REPLACE FUNCTION sala_libre(
    p_sala integer,
    p_inicio timestamp,
    p_fin timestamp,
    p_excluir integer DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql STABLE
AS $$
    SELECT NOT EXISTS (
        SELECT 1
        FROM reserva AS r
        WHERE r.id_sala = p_sala
          AND r.estado = 'activa'
          AND r.inicio < p_fin
          AND p_inicio < r.fin
          AND (p_excluir IS NULL OR r.id <> p_excluir)
    );
$$;

-- A2: verificaciones y resultados esperados.
SELECT codigo,
       horas_semana(codigo, dia(1)) AS proxima,
       horas_semana(codigo, dia(-13)) AS pasada
FROM estudiante
ORDER BY codigo;
-- Esperado: proxima: Ana 5.0, Bruno 2.0, Carla 3.0, Diego 2.0,
-- Elena 0.0, Felipe 0.0; pasada: Bruno 2.0, Carla 2.0, Felipe 2.0,
-- los demas 0.0.

SELECT sala_libre(1, dia(1) + TIME '09:00', dia(1) + TIME '11:00') AS a,
       sala_libre(1, dia(1) + TIME '12:00', dia(1) + TIME '14:00') AS b,
       sala_libre(2, dia(3) + TIME '08:00', dia(3) + TIME '10:00') AS c,
       sala_libre(1, dia(1) + TIME '08:00', dia(1) + TIME '10:00', 1) AS d;
-- Esperado: a = false, b = true, c = true, d = true.

-- A3(a): reservar valida las reglas 5, 2, 3 y 4, en ese orden.
CREATE OR REPLACE PROCEDURE reservar(
    p_codigo varchar,
    p_sala integer,
    p_inicio timestamp,
    p_fin timestamp,
    p_asistentes integer
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_nombre estudiante.nombre%TYPE;
    v_sancionado_hasta estudiante.sancionado_hasta%TYPE;
    v_capacidad sala.capacidad%TYPE;
    v_activa sala.activa%TYPE;
    v_horas_actuales numeric;
    v_horas_solicitadas numeric;
    v_id reserva.id%TYPE;
BEGIN
    SELECT e.nombre, e.sancionado_hasta
    INTO v_nombre, v_sancionado_hasta
    FROM estudiante AS e
    WHERE e.codigo = p_codigo;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El estudiante % no existe', p_codigo;
    END IF;

    IF v_sancionado_hasta >= CURRENT_DATE THEN
        RAISE EXCEPTION 'El estudiante % está sancionado hasta %',
            v_nombre, v_sancionado_hasta;
    END IF;

    SELECT s.capacidad, s.activa
    INTO v_capacidad, v_activa
    FROM sala AS s
    WHERE s.id_sala = p_sala;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La sala % no existe', p_sala;
    END IF;

    IF NOT v_activa THEN
        RAISE EXCEPTION 'La sala % está en mantenimiento', p_sala;
    END IF;

    IF p_asistentes > v_capacidad THEN
        RAISE EXCEPTION 'La sala % tiene capacidad para %, no para % asistentes',
            p_sala, v_capacidad, p_asistentes;
    END IF;

    IF NOT sala_libre(p_sala, p_inicio, p_fin) THEN
        RAISE EXCEPTION 'La sala % está ocupada en el horario solicitado', p_sala;
    END IF;

    v_horas_actuales := horas_semana(p_codigo, p_inicio::date);
    v_horas_solicitadas := EXTRACT(EPOCH FROM (p_fin - p_inicio)) / 3600;

    IF v_horas_actuales + v_horas_solicitadas > 6 THEN
        RAISE EXCEPTION
            'El estudiante % superaría las 6 horas semanales (lleva % horas)',
            v_nombre, v_horas_actuales;
    END IF;

    INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
    VALUES (p_sala, p_codigo, p_inicio, p_fin, p_asistentes)
    RETURNING id INTO v_id;

    RAISE NOTICE 'Reserva % creada para % en la sala %',
        v_id, v_nombre, p_sala;
END;
$$;

-- A3(b): cancelar solo permite reservas activas que aun no han empezado.
CREATE OR REPLACE PROCEDURE cancelar(p_id integer)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado reserva.estado%TYPE;
    v_inicio reserva.inicio%TYPE;
BEGIN
    SELECT r.estado, r.inicio
    INTO v_estado, v_inicio
    FROM reserva AS r
    WHERE r.id = p_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La reserva % no existe', p_id;
    END IF;

    IF v_estado <> 'activa' THEN
        RAISE EXCEPTION 'La reserva % no está activa', p_id;
    END IF;

    IF v_inicio <= LOCALTIMESTAMP THEN
        RAISE EXCEPTION 'La reserva % ya empezó', p_id;
    END IF;

    UPDATE reserva
    SET estado = 'cancelada'
    WHERE id = p_id;

    RAISE NOTICE 'Reserva % cancelada', p_id;
END;
$$;

-- A3(c): bateria de procedimientos.
CALL reservar('2610005', 1, dia(4) + TIME '08:00', dia(4) + TIME '10:00', 2);
-- Esperado: error, Elena está sancionada.

CALL reservar('2610006', 4, dia(4) + TIME '08:00', dia(4) + TIME '10:00', 2);
-- Esperado: error, sala en mantenimiento.

CALL reservar('2610006', 1, dia(4) + TIME '08:00', dia(4) + TIME '10:00', 5);
-- Esperado: error, capacidad 4, no 5.

CALL reservar('2610006', 1, dia(1) + TIME '09:00', dia(1) + TIME '11:00', 2);
-- Esperado: error, sala ocupada.

CALL reservar('2610001', 2, dia(4) + TIME '08:00', dia(4) + TIME '10:00', 3);
-- Esperado: error, Ana superaria las 6 horas semanales (lleva 5.0).

CALL reservar('2610006', 1, dia(1) + TIME '12:00', dia(1) + TIME '14:00', 3);
-- Esperado: reserva creada.

CALL reservar('2610004', 2, dia(3) + TIME '08:00', dia(3) + TIME '10:00', 4);
-- Esperado: reserva creada; la reserva anterior estaba cancelada.

CALL reservar('2610001', 2, dia(4) + TIME '08:00', dia(4) + TIME '09:00', 3);
-- Esperado: reserva creada; Ana llega justo a 6 horas.

CALL reservar('2610099', 2, dia(4) + TIME '08:00', dia(4) + TIME '09:00', 3);
-- Esperado: error, el estudiante no existe.

CALL cancelar(7);
-- Esperado: error, la reserva 7 no está activa.

CALL cancelar(2);
-- Esperado: cancela la reserva activa de Bruno.

-- A4(a): antes del trigger, un INSERT directo puede saltarse capacidad y cruce.
BEGIN;
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (3, '2610005', dia(2) + TIME '10:00', dia(2) + TIME '11:00', 12);
-- Esperado: pasa sin el trigger aunque excede la capacidad y se cruza con Ana.
ROLLBACK;

-- A4(b): estas reglas aplican a toda reserva activa, incluso con INSERT/UPDATE
-- directo. En UPDATE se excluye NEW.id para que la fila no choque consigo misma.
CREATE OR REPLACE FUNCTION validar_reserva()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_capacidad sala.capacidad%TYPE;
    v_activa sala.activa%TYPE;
BEGIN
    IF NEW.estado <> 'activa' THEN
        RETURN NEW;
    END IF;

    SELECT s.capacidad, s.activa
    INTO v_capacidad, v_activa
    FROM sala AS s
    WHERE s.id_sala = NEW.id_sala;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La sala % no existe', NEW.id_sala;
    END IF;

    IF NOT v_activa THEN
        RAISE EXCEPTION 'La sala % está en mantenimiento', NEW.id_sala;
    END IF;

    IF NEW.asistentes > v_capacidad THEN
        RAISE EXCEPTION 'La sala % tiene capacidad para %, no para % asistentes',
            NEW.id_sala, v_capacidad, NEW.asistentes;
    END IF;

    IF NOT sala_libre(NEW.id_sala, NEW.inicio, NEW.fin, NEW.id) THEN
        RAISE EXCEPTION 'La sala % está ocupada en el horario solicitado',
            NEW.id_sala;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reserva_validar ON reserva;
CREATE TRIGGER reserva_validar
BEFORE INSERT OR UPDATE ON reserva
FOR EACH ROW
EXECUTE FUNCTION validar_reserva();

-- A4(c): batería del trigger.
INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (3, '2610005', dia(2) + TIME '10:00', dia(2) + TIME '11:00', 12);
-- Esperado: falla por capacidad.

INSERT INTO reserva (id_sala, codigo, inicio, fin, asistentes)
VALUES (3, '2610005', dia(2) + TIME '10:00', dia(2) + TIME '11:00', 6);
-- Esperado: falla porque la sala está ocupada por la reserva 4.

UPDATE reserva
SET inicio = dia(3) + TIME '09:00'
WHERE id = 6;
-- Esperado: falla; se cruza con la reserva de Diego de las 08:00.

UPDATE reserva
SET asistentes = 5
WHERE id = 6;
-- Esperado: pasa; sala_libre excluye la propia reserva 6.

UPDATE reserva
SET estado = 'activa'
WHERE id = 5;
-- Esperado: falla; reactivarla se cruza con la reserva de Diego de las 08:00.

-- A4(d): el INSERT directo de Elena en A4(a) pasa antes del trigger porque
-- reservar() no se ejecuta y las reglas de sanción no son CHECKs.
-- Las reglas 4 y 5 corresponden al flujo de reserva de un estudiante y se
-- validan en reservar(). No deben imponerse indiscriminadamente en este
-- trigger: coordinación puede crear reservas por otros motivos (por ejemplo,
-- un evento de 4 horas a nombre de un monitor). Para impedir que usuarios
-- finales evadan esas reglas con DML directo, se debe restringir ese acceso
-- o modelar el actor/motivo y aplicar la política adecuada en la base.
