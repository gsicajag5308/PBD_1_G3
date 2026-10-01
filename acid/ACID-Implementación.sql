-- Ejecutar como SYS después de ejecutar proyecto_v1.sql.
-- Este procedimiento realiza una transferencia completa entre dos cuentas.

CREATE OR REPLACE PROCEDURE BANCO_CORE.REALIZAR_TRANSFERENCIA (
    p_id_cuenta_origen  IN  NUMBER,
    p_id_cuenta_destino IN  NUMBER,
    p_monto             IN  NUMBER,
    p_id_usuario        IN  NUMBER,
    p_id_transferencia  OUT NUMBER
) AS
    v_saldo_origen    BANCO_CORE.CUENTAS.SALDO%TYPE;
    v_saldo_destino   BANCO_CORE.CUENTAS.SALDO%TYPE;
    v_estado_origen   BANCO_CORE.CUENTAS.ESTADO%TYPE;
    v_estado_destino  BANCO_CORE.CUENTAS.ESTADO%TYPE;
    v_estado_usuario  BANCO_CORE.USUARIOS_SISTEMA.ESTADO%TYPE;
    v_id_pendiente    NUMBER;
    v_id_completada   NUMBER;
    v_id_debito       NUMBER;
    v_id_credito      NUMBER;
BEGIN
    p_id_transferencia := NULL;

    -- Revisamos los datos recibidos.
    IF p_id_cuenta_origen IS NULL OR p_id_cuenta_destino IS NULL THEN
        RAISE_APPLICATION_ERROR(-20001, 'Debe indicar las dos cuentas.');
    END IF;

    IF p_id_cuenta_origen = p_id_cuenta_destino THEN
        RAISE_APPLICATION_ERROR(-20002, 'Las cuentas deben ser diferentes.');
    END IF;

    IF p_monto IS NULL OR p_monto <= 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'El monto debe ser mayor que cero.');
    END IF;

    -- Comprobamos que el usuario exista y esté activo.
    BEGIN
        SELECT ESTADO
        INTO v_estado_usuario
        FROM BANCO_CORE.USUARIOS_SISTEMA
        WHERE ID_USUARIO = p_id_usuario;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20004, 'El usuario no existe.');
    END;

    IF v_estado_usuario <> 'A' THEN
        RAISE_APPLICATION_ERROR(-20005, 'El usuario está inactivo.');
    END IF;

    -- Bloqueamos las cuentas para que otra transferencia no las cambie al mismo tiempo.
    BEGIN
        IF p_id_cuenta_origen < p_id_cuenta_destino THEN
            SELECT SALDO, ESTADO
            INTO v_saldo_origen, v_estado_origen
            FROM BANCO_CORE.CUENTAS
            WHERE ID_CUENTA = p_id_cuenta_origen
            FOR UPDATE;

            SELECT SALDO, ESTADO
            INTO v_saldo_destino, v_estado_destino
            FROM BANCO_CORE.CUENTAS
            WHERE ID_CUENTA = p_id_cuenta_destino
            FOR UPDATE;
        ELSE
            SELECT SALDO, ESTADO
            INTO v_saldo_destino, v_estado_destino
            FROM BANCO_CORE.CUENTAS
            WHERE ID_CUENTA = p_id_cuenta_destino
            FOR UPDATE;

            SELECT SALDO, ESTADO
            INTO v_saldo_origen, v_estado_origen
            FROM BANCO_CORE.CUENTAS
            WHERE ID_CUENTA = p_id_cuenta_origen
            FOR UPDATE;
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20006, 'Una de las cuentas no existe.');
    END;

    IF v_estado_origen <> 'A' OR v_estado_destino <> 'A' THEN
        RAISE_APPLICATION_ERROR(-20007, 'Las dos cuentas deben estar activas.');
    END IF;

    IF v_saldo_origen < p_monto THEN
        RAISE_APPLICATION_ERROR(-20008, 'La cuenta no tiene saldo suficiente.');
    END IF;

    -- Buscamos los datos necesarios de los catálogos.
    BEGIN
        SELECT ID_ESTADO_TRANSFERENCIA
        INTO v_id_pendiente
        FROM BANCO_CATALOGO.ESTADOS_TRANSFERENCIA
        WHERE UPPER(NOMBRE_ESTADO) = 'PENDIENTE';

        SELECT ID_ESTADO_TRANSFERENCIA
        INTO v_id_completada
        FROM BANCO_CATALOGO.ESTADOS_TRANSFERENCIA
        WHERE UPPER(NOMBRE_ESTADO) = 'COMPLETADA';

        SELECT ID_TIPO_MOVIMIENTO
        INTO v_id_debito
        FROM BANCO_CATALOGO.TIPOS_MOVIMIENTO
        WHERE UPPER(NOMBRE_TIPO) = 'DEBITO';

        SELECT ID_TIPO_MOVIMIENTO
        INTO v_id_credito
        FROM BANCO_CATALOGO.TIPOS_MOVIMIENTO
        WHERE UPPER(NOMBRE_TIPO) = 'CREDITO';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20009, 'Faltan datos en los catálogos.');
    END;

    -- Creamos la transferencia.
    INSERT INTO BANCO_CORE.TRANSFERENCIAS (
        ID_CUENTA_ORIGEN,
        ID_CUENTA_DESTINO,
        MONTO,
        ID_ESTADO_TRANSFERENCIA,
        FECHA_TRANSACCION,
        ID_USUARIO
    ) VALUES (
        p_id_cuenta_origen,
        p_id_cuenta_destino,
        p_monto,
        v_id_pendiente,
        SYSTIMESTAMP,
        p_id_usuario
    )
    RETURNING ID_TRANSFERENCIA INTO p_id_transferencia;

    -- Restamos el dinero de la cuenta origen.
    UPDATE BANCO_CORE.CUENTAS
    SET SALDO = SALDO - p_monto,
        FECHA_ULTIMA_MOD = SYSTIMESTAMP
    WHERE ID_CUENTA = p_id_cuenta_origen;

    v_saldo_origen := v_saldo_origen - p_monto;

    INSERT INTO BANCO_CORE.MOVIMIENTOS_CUENTA (
        ID_CUENTA,
        ID_TIPO_MOVIMIENTO,
        DEBITO,
        CREDITO,
        SALDO_RESULTANTE,
        FECHA,
        ID_TRANSFERENCIA
    ) VALUES (
        p_id_cuenta_origen,
        v_id_debito,
        p_monto,
        0,
        v_saldo_origen,
        SYSTIMESTAMP,
        p_id_transferencia
    );

    -- Sumamos el dinero a la cuenta destino.
    UPDATE BANCO_CORE.CUENTAS
    SET SALDO = SALDO + p_monto,
        FECHA_ULTIMA_MOD = SYSTIMESTAMP
    WHERE ID_CUENTA = p_id_cuenta_destino;

    v_saldo_destino := v_saldo_destino + p_monto;

    INSERT INTO BANCO_CORE.MOVIMIENTOS_CUENTA (
        ID_CUENTA,
        ID_TIPO_MOVIMIENTO,
        DEBITO,
        CREDITO,
        SALDO_RESULTANTE,
        FECHA,
        ID_TRANSFERENCIA
    ) VALUES (
        p_id_cuenta_destino,
        v_id_credito,
        0,
        p_monto,
        v_saldo_destino,
        SYSTIMESTAMP,
        p_id_transferencia
    );

    -- Marcamos la transferencia como completada.
    UPDATE BANCO_CORE.TRANSFERENCIAS
    SET ID_ESTADO_TRANSFERENCIA = v_id_completada
    WHERE ID_TRANSFERENCIA = p_id_transferencia;

    -- Guardamos toda la transferencia.
    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        -- Si algo falla, deshacemos todos los cambios.
        ROLLBACK;
        p_id_transferencia := NULL;
        RAISE;
END REALIZAR_TRANSFERENCIA;
/

GRANT EXECUTE ON BANCO_CORE.REALIZAR_TRANSFERENCIA
TO ROL_OPERADOR_TRANSFERENCIAS;

GRANT EXECUTE ON BANCO_CORE.REALIZAR_TRANSFERENCIA
TO ROL_ADMIN_BANCO;

-- El procedimiento debe aparecer con estado VALID.
SELECT OWNER, OBJECT_NAME, OBJECT_TYPE, STATUS
FROM DBA_OBJECTS
WHERE OWNER = 'BANCO_CORE'
  AND OBJECT_NAME = 'REALIZAR_TRANSFERENCIA';

-- Esta consulta mostrará información solamente si hubo un error de compilación.
SELECT OWNER, NAME, TYPE, LINE, POSITION, TEXT
FROM DBA_ERRORS
WHERE OWNER = 'BANCO_CORE'
  AND NAME = 'REALIZAR_TRANSFERENCIA'
ORDER BY SEQUENCE;

