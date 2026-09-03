--==============================================================================
-- PASO 1: Permitir crear usuarios sin restricciones de contraseña
--==============================================================================

ALTER SESSION SET "_ORACLE_SCRIPT" = true;

ALTER TABLE BANCO_CORE.TRANSFERENCIAS
ADD DESCRIPCION VARCHAR2(200);
/*

SELECT COLUMN_NAME, DATA_TYPE, DATA_LENGTH, NULLABLE
FROM DBA_TAB_COLUMNS
WHERE OWNER = 'BANCO_CORE' AND TABLE_NAME = 'TRANSFERENCIAS'
ORDER BY COLUMN_ID;
*/
CREATE OR REPLACE PROCEDURE BANCO_CORE.PRC_TRANSFERENCIA_TIMESTAMP (
    p_cuenta_origen  IN BANCO_CORE.CUENTAS.ID_CUENTA%TYPE,
    p_cuenta_destino IN BANCO_CORE.CUENTAS.ID_CUENTA%TYPE,
    p_monto          IN NUMBER,
    p_usuario_exec   IN BANCO_CORE.USUARIOS_SISTEMA.ID_USUARIO%TYPE,
    p_descripcion    IN VARCHAR2 DEFAULT 'Transferencia bancaria'
) IS
    v_max_intentos   CONSTANT NUMBER := 5;
    v_intentos       NUMBER := 0;
    v_exito          BOOLEAN := FALSE;
    v_id_transf      NUMBER;
    v_id_estado_comp NUMBER;
    v_id_tipo_deb    NUMBER;
    v_id_tipo_cred   NUMBER;
    v_saldo_origen   NUMBER;
    v_saldo_destino  NUMBER;

    e_cannot_serialize EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_cannot_serialize, -8177);
BEGIN
    SELECT ID_ESTADO_TRANSFERENCIA INTO v_id_estado_comp
      FROM BANCO_CATALOGO.ESTADOS_TRANSFERENCIA WHERE NOMBRE_ESTADO = 'COMPLETADA';

    SELECT ID_TIPO_MOVIMIENTO INTO v_id_tipo_deb
      FROM BANCO_CATALOGO.TIPOS_MOVIMIENTO WHERE NOMBRE_TIPO = 'DEBITO';

    SELECT ID_TIPO_MOVIMIENTO INTO v_id_tipo_cred
      FROM BANCO_CATALOGO.TIPOS_MOVIMIENTO WHERE NOMBRE_TIPO = 'CREDITO';

    WHILE NOT v_exito AND v_intentos < v_max_intentos LOOP
        BEGIN
            v_intentos := v_intentos + 1;

            SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

            UPDATE BANCO_CORE.CUENTAS
               SET SALDO = SALDO - p_monto
             WHERE ID_CUENTA = p_cuenta_origen
            RETURNING SALDO INTO v_saldo_origen;

            UPDATE BANCO_CORE.CUENTAS
               SET SALDO = SALDO + p_monto
             WHERE ID_CUENTA = p_cuenta_destino
            RETURNING SALDO INTO v_saldo_destino;

            INSERT INTO BANCO_CORE.TRANSFERENCIAS (
                ID_CUENTA_ORIGEN, ID_CUENTA_DESTINO, MONTO,
                ID_ESTADO_TRANSFERENCIA, FECHA_TRANSACCION, ID_USUARIO, DESCRIPCION
            ) VALUES (
                p_cuenta_origen, p_cuenta_destino, p_monto,
                v_id_estado_comp, SYSTIMESTAMP, p_usuario_exec, p_descripcion
            ) RETURNING ID_TRANSFERENCIA INTO v_id_transf;

            INSERT INTO BANCO_CORE.MOVIMIENTOS_CUENTA (
                ID_CUENTA, ID_TIPO_MOVIMIENTO, DEBITO, CREDITO,
                SALDO_RESULTANTE, FECHA, ID_TRANSFERENCIA
            ) VALUES (
                p_cuenta_origen, v_id_tipo_deb, p_monto, 0,
                v_saldo_origen, SYSTIMESTAMP, v_id_transf
            );

            INSERT INTO BANCO_CORE.MOVIMIENTOS_CUENTA (
                ID_CUENTA, ID_TIPO_MOVIMIENTO, DEBITO, CREDITO,
                SALDO_RESULTANTE, FECHA, ID_TRANSFERENCIA
            ) VALUES (
                p_cuenta_destino, v_id_tipo_cred, 0, p_monto,
                v_saldo_destino, SYSTIMESTAMP, v_id_transf
            );

            COMMIT;
            v_exito := TRUE;
        EXCEPTION
            WHEN e_cannot_serialize THEN
                ROLLBACK;
                IF v_intentos >= v_max_intentos THEN
                    RAISE_APPLICATION_ERROR(-20001,
                        'Error: se excedió el límite de reintentos por alta concurrencia.');
                END IF;
                DBMS_SESSION.SLEEP(DBMS_RANDOM.VALUE(0.05, 0.15));
            WHEN OTHERS THEN
                ROLLBACK;
                RAISE;
        END;
    END LOOP;
END PRC_TRANSFERENCIA_TIMESTAMP;
/

--------------------------------------------------------------------------------
-- PRUEBA DE EJECUCIÓN CONCURRENTE
--------------------------------------------------------------------------------


SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

UPDATE BANCO_CORE.CUENTAS SET SALDO = SALDO - 50 WHERE ID_CUENTA = 1;

-- NO hagas COMMIT todavía. Deja esta sesión "congelada" aquí.

EXEC BANCO_CORE.prc_transferencia_timestamp(1, 2, 100, 1, 'Prueba concurrencia B');

--
COMMIT;
