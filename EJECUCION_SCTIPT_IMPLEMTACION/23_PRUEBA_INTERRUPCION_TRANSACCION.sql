-- PRUEBA DE ATOMICIDAD: INTERRUPCION DE UNA TRANSFERENCIA
-- Conexion: BANCO_CORE_PROYECTO, usuario BANCO_CORE.
-- Ejecutar cada paso por separado, seleccionando su bloque y pulsando F5.
-- Usar una sesion sin otras operaciones pendientes.
-- El fallo se provoca al acreditar el destino, despues del debito.
-- No ejecutar COMMIT ni ROLLBACK manual durante la prueba.

-- PASO 1: Consultar el estado inicial.
-- Estos valores se compararan con los obtenidos despues del fallo.
-- Captura: 25_INTERRUPCION_estado_inicial.png

SELECT USER AS USUARIO FROM DUAL;

SELECT NUMERO_CUENTA, SALDO
FROM BANCO_CORE.CUENTAS
WHERE NUMERO_CUENTA IN ('001-0001', '001-0002')
ORDER BY NUMERO_CUENTA;

SELECT COUNT(*) AS TOTAL_TRANSFERENCIAS
FROM BANCO_CORE.TRANSFERENCIAS;

SELECT COUNT(*) AS TOTAL_MOVIMIENTOS
FROM BANCO_CORE.MOVIMIENTOS_CUENTA;


-- PASO 2: Crear el trigger temporal para simular el fallo.
-- Solo actua cuando la sesion tiene el identificador PRUEBA_FALLO_ACID
-- y se intenta incrementar el saldo de la cuenta destino 001-0002.
-- Captura: 26_INTERRUPCION_trigger_temporal.png

CREATE OR REPLACE TRIGGER BANCO_CORE.TRG_PRUEBA_FALLO_ACID
BEFORE UPDATE OF SALDO ON BANCO_CORE.CUENTAS
FOR EACH ROW
BEGIN
    IF SYS_CONTEXT('USERENV', 'CLIENT_IDENTIFIER') = 'PRUEBA_FALLO_ACID'
       AND :NEW.NUMERO_CUENTA = '001-0002'
       AND :NEW.SALDO > :OLD.SALDO
    THEN
        RAISE_APPLICATION_ERROR(
            -20991,
            'Fallo simulado al acreditar la cuenta destino.'
        );
    END IF;
END;
/


-- PASO 3: Identificar la sesion e intentar transferir Q100.
-- Ejecutar ambos bloques en la misma hoja y conexion.
-- El procedimiento registra la transferencia, aplica el debito
-- e inserta su movimiento antes de intentar acreditar el destino.
-- En ese momento, el trigger genera el error ORA-20991.
-- El procedimiento ejecuta su ROLLBACK y devuelve el error.
-- El error es intencional: continuar despues con el paso 4.
-- Captura: 27_INTERRUPCION_error_simulado.png

BEGIN
    DBMS_SESSION.SET_IDENTIFIER('PRUEBA_FALLO_ACID');
END;
/

DECLARE
    v_origen        NUMBER;
    v_destino       NUMBER;
    v_usuario       NUMBER;
    v_transferencia NUMBER;
BEGIN
    -- Buscar las cuentas y el usuario utilizados en la prueba.
    SELECT ID_CUENTA INTO v_origen
    FROM BANCO_CORE.CUENTAS
    WHERE NUMERO_CUENTA = '001-0001';

    SELECT ID_CUENTA INTO v_destino
    FROM BANCO_CORE.CUENTAS
    WHERE NUMERO_CUENTA = '001-0002';

    SELECT ID_USUARIO INTO v_usuario
    FROM BANCO_CORE.USUARIOS_SISTEMA
    WHERE NOMBRE_USUARIO = 'operador1';

    -- Llamar al procedimiento original, sin modificarlo.
    BANCO_CORE.REALIZAR_TRANSFERENCIA(
        v_origen,
        v_destino,
        100,
        v_usuario,
        v_transferencia
    );
END;
/


-- PASO 4: Comprobar la recuperacion sin hacer ROLLBACK manual.
-- Los saldos y las cantidades de registros deben coincidir con el paso 1.
-- Durante la prueba realizada se conservaron:
-- Q14900 en origen, Q4100 en destino, 10 transferencias y 14 movimientos.
-- Esto demuestra que el fallo no dejo una transferencia incompleta.
-- Captura: 28_INTERRUPCION_recuperacion.png

SELECT NUMERO_CUENTA, SALDO
FROM BANCO_CORE.CUENTAS
WHERE NUMERO_CUENTA IN ('001-0001', '001-0002')
ORDER BY NUMERO_CUENTA;

SELECT COUNT(*) AS TOTAL_TRANSFERENCIAS
FROM BANCO_CORE.TRANSFERENCIAS;

SELECT COUNT(*) AS TOTAL_MOVIMIENTOS
FROM BANCO_CORE.MOVIMIENTOS_CUENTA;


-- PASO 5: Retirar los elementos temporales de la prueba.
-- Limpiar el identificador de la sesion y eliminar el trigger.
-- La consulta final no debe devolver filas.
-- Captura: 29_INTERRUPCION_limpieza.png

BEGIN
    DBMS_SESSION.CLEAR_IDENTIFIER;
END;
/

DROP TRIGGER BANCO_CORE.TRG_PRUEBA_FALLO_ACID;

SELECT TRIGGER_NAME
FROM USER_TRIGGERS
WHERE TRIGGER_NAME = 'TRG_PRUEBA_FALLO_ACID';

-- Resultado: se comprobo la atomicidad ante un fallo intermedio.
-- Los cambios de la transferencia se revirtieron completamente.
-- El procedimiento REALIZAR_TRANSFERENCIA se conservo sin modificaciones.