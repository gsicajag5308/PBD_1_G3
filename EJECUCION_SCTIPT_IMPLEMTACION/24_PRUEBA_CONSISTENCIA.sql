-- PRUEBA DE CONSISTENCIA
-- Conexion: BANCO_CORE_PROYECTO.
-- PASO 1: Registrar los saldos y registros antes de la prueba.

SELECT USER AS USUARIO FROM DUAL;

SELECT NUMERO_CUENTA, SALDO
FROM BANCO_CORE.CUENTAS
WHERE NUMERO_CUENTA IN ('001-0001', '001-0002')
ORDER BY NUMERO_CUENTA;

SELECT COUNT(*) AS TOTAL_TRANSFERENCIAS
FROM BANCO_CORE.TRANSFERENCIAS;

SELECT COUNT(*) AS TOTAL_MOVIMIENTOS
FROM BANCO_CORE.MOVIMIENTOS_CUENTA;


-- PASO 2: Intentar una transferencia con fondos insuficientes.
-- Se solicitan Q15000, pero la cuenta origen tiene Q14900.
-- Se espera ORA-20008: La cuenta no tiene saldo suficiente.

DECLARE
    v_origen        NUMBER;
    v_destino       NUMBER;
    v_usuario       NUMBER;
    v_transferencia NUMBER;
BEGIN
    SELECT ID_CUENTA INTO v_origen
    FROM BANCO_CORE.CUENTAS
    WHERE NUMERO_CUENTA = '001-0001';

    SELECT ID_CUENTA INTO v_destino
    FROM BANCO_CORE.CUENTAS
    WHERE NUMERO_CUENTA = '001-0002';

    SELECT ID_USUARIO INTO v_usuario
    FROM BANCO_CORE.USUARIOS_SISTEMA
    WHERE NOMBRE_USUARIO = 'operador1';

    BANCO_CORE.REALIZAR_TRANSFERENCIA(
        v_origen,
        v_destino,
        15000,
        v_usuario,
        v_transferencia
    );
END;
/

-- PASO 3: Verificar que el intento rechazado no altero los datos.

SELECT NUMERO_CUENTA, SALDO
FROM BANCO_CORE.CUENTAS
WHERE NUMERO_CUENTA IN ('001-0001', '001-0002')
ORDER BY NUMERO_CUENTA;

SELECT COUNT(*) AS TOTAL_TRANSFERENCIAS
FROM BANCO_CORE.TRANSFERENCIAS;

SELECT COUNT(*) AS TOTAL_MOVIMIENTOS
FROM BANCO_CORE.MOVIMIENTOS_CUENTA;