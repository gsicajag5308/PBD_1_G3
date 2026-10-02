/*==============================================================================
  PROYECTO: MODULO DE TRANSFERENCIAS INTERCUENTAS - ORACLE XE 21c
  REQUISITO 5: USO ESTRATEGICO DE SAVEPOINTS PARA RECUPERACION PARCIAL
  ESQUEMAS: BANCO_CORE (transaccional) / BANCO_CATALOGO (catalogos)
==============================================================================*/

/*  ARCHIVO 02 - EJECUTAR CONECTADO COMO BANCO_CORE
    Pruebas y consultas de evidencia. Ejecutar sentencia por sentencia        */

SET SERVEROUTPUT ON SIZE UNLIMITED;

/*==============================================================================
  SECCION 6: PRUEBAS Y EVIDENCIA
==============================================================================*/

--------------------------------------------------------------------------------
-- 6.0 Estado inicial
--------------------------------------------------------------------------------
SELECT ID_CUENTA, NUMERO_CUENTA, SALDO, ESTADO
FROM BANCO_CORE.CUENTAS
ORDER BY ID_CUENTA;


--------------------------------------------------------------------------------
-- 6.1 PRUEBA MANUAL: savepoints en sesion interactiva
--     Demuestra el mecanismo desnudo, sin PL/SQL de por medio.
--------------------------------------------------------------------------------
SAVEPOINT SP_MANUAL_A;

UPDATE BANCO_CORE.CUENTAS
   SET SALDO = SALDO - 100, FECHA_ULTIMA_MOD = SYSTIMESTAMP
 WHERE NUMERO_CUENTA = '001-0001';

SAVEPOINT SP_MANUAL_B;

UPDATE BANCO_CORE.CUENTAS
   SET SALDO = SALDO - 50, FECHA_ULTIMA_MOD = SYSTIMESTAMP
 WHERE NUMERO_CUENTA = '001-0002';

-- Se arrepiente del segundo cargo pero quiere conservar el primero:
ROLLBACK TO SP_MANUAL_B;

SELECT NUMERO_CUENTA, SALDO FROM BANCO_CORE.CUENTAS
WHERE NUMERO_CUENTA IN ('001-0001', '001-0002');
-- 001-0001 conserva el -100, 001-0002 quedo intacta.

ROLLBACK;   -- se descarta toda la prueba manual


--------------------------------------------------------------------------------
-- 6.2 PRUEBA A: transferencia exitosa
--------------------------------------------------------------------------------
DECLARE
    v_c1 NUMBER; v_c2 NUMBER; v_usr NUMBER; v_res VARCHAR2(300);
BEGIN
    SELECT ID_CUENTA INTO v_c1 FROM BANCO_CORE.CUENTAS WHERE NUMERO_CUENTA = '001-0001';
    SELECT ID_CUENTA INTO v_c2 FROM BANCO_CORE.CUENTAS WHERE NUMERO_CUENTA = '001-0002';
    SELECT MIN(ID_USUARIO) INTO v_usr FROM BANCO_CORE.USUARIOS_SISTEMA;

    BANCO_CORE.PRC_TRANSFERENCIA_SP(v_c1, v_c2, 250, v_usr, v_res);
    DBMS_OUTPUT.PUT_LINE('PRUEBA A -> ' || v_res);
END;
/


--------------------------------------------------------------------------------
-- 6.3 PRUEBA B: recuperacion parcial (falla el historico)
--     Esperado: PARCIAL. Los saldos cambian, el encabezado queda grabado con
--     estado PARCIAL y NO se generan filas en MOVIMIENTOS_CUENTA.
--------------------------------------------------------------------------------
DECLARE
    v_c1 NUMBER; v_c2 NUMBER; v_usr NUMBER; v_res VARCHAR2(300);
BEGIN
    SELECT ID_CUENTA INTO v_c1 FROM BANCO_CORE.CUENTAS WHERE NUMERO_CUENTA = '001-0001';
    SELECT ID_CUENTA INTO v_c2 FROM BANCO_CORE.CUENTAS WHERE NUMERO_CUENTA = '001-0002';
    SELECT MIN(ID_USUARIO) INTO v_usr FROM BANCO_CORE.USUARIOS_SISTEMA;

    BANCO_CORE.PRC_TRANSFERENCIA_SP(
        p_cuenta_origen  => v_c1,
        p_cuenta_destino => v_c2,
        p_monto          => 300,
        p_id_usuario     => v_usr,
        p_resultado      => v_res,
        p_commit         => 'S',
        p_simular_fallo  => 'S');

    DBMS_OUTPUT.PUT_LINE('PRUEBA B -> ' || v_res);
END;
/


--------------------------------------------------------------------------------
-- 6.4 PRUEBA C: sobregiro (reversion total hasta SP_INICIO)
--------------------------------------------------------------------------------
DECLARE
    v_c1 NUMBER; v_c2 NUMBER; v_usr NUMBER; v_res VARCHAR2(300);
BEGIN
    SELECT ID_CUENTA INTO v_c1 FROM BANCO_CORE.CUENTAS WHERE NUMERO_CUENTA = '001-0001';
    SELECT ID_CUENTA INTO v_c2 FROM BANCO_CORE.CUENTAS WHERE NUMERO_CUENTA = '001-0002';
    SELECT MIN(ID_USUARIO) INTO v_usr FROM BANCO_CORE.USUARIOS_SISTEMA;

    BANCO_CORE.PRC_TRANSFERENCIA_SP(v_c1, v_c2, 99999999, v_usr, v_res);
    DBMS_OUTPUT.PUT_LINE('PRUEBA C -> ' || v_res);
END;
/


--------------------------------------------------------------------------------
-- 6.5 PRUEBA D: lote mixto. La operacion 2 falla por sobregiro,
--     las operaciones 1 y 3 se confirman igual.
--------------------------------------------------------------------------------
DECLARE
    v_c1 NUMBER; v_c2 NUMBER; v_usr NUMBER;
BEGIN
    SELECT ID_CUENTA INTO v_c1 FROM BANCO_CORE.CUENTAS WHERE NUMERO_CUENTA = '001-0001';
    SELECT ID_CUENTA INTO v_c2 FROM BANCO_CORE.CUENTAS WHERE NUMERO_CUENTA = '001-0002';
    SELECT MIN(ID_USUARIO) INTO v_usr FROM BANCO_CORE.USUARIOS_SISTEMA;

    BANCO_CORE.PRC_LOTE_TRANSFERENCIAS(
        BANCO_CORE.T_LOTE_TRANSFERENCIAS(
            BANCO_CORE.T_TRANSFERENCIA_ITEM(v_c1, v_c2, 100),
            BANCO_CORE.T_TRANSFERENCIA_ITEM(v_c1, v_c2, 99999999),  -- falla
            BANCO_CORE.T_TRANSFERENCIA_ITEM(v_c2, v_c1, 75)
        ),
        v_usr);
END;
/


--------------------------------------------------------------------------------
-- 6.6 VERIFICACION FINAL
--------------------------------------------------------------------------------

-- Saldos resultantes
SELECT ID_CUENTA, NUMERO_CUENTA, SALDO, FECHA_ULTIMA_MOD
FROM BANCO_CORE.CUENTAS
ORDER BY ID_CUENTA;

-- Transferencias con su estado. Las PARCIAL son las candidatas a reproceso.
SELECT T.ID_TRANSFERENCIA, T.ID_CUENTA_ORIGEN, T.ID_CUENTA_DESTINO,
       T.MONTO, E.NOMBRE_ESTADO, T.FECHA_TRANSACCION
FROM BANCO_CORE.TRANSFERENCIAS T
JOIN BANCO_CATALOGO.ESTADOS_TRANSFERENCIA E
  ON E.ID_ESTADO_TRANSFERENCIA = T.ID_ESTADO_TRANSFERENCIA
ORDER BY T.ID_TRANSFERENCIA DESC;

-- Prueba de que el ROLLBACK TO SAVEPOINT si borro el historico:
-- las transferencias PARCIAL no tienen filas en MOVIMIENTOS_CUENTA.
SELECT T.ID_TRANSFERENCIA, E.NOMBRE_ESTADO,
       COUNT(M.ID_MOVIMIENTO) AS MOVIMIENTOS_REGISTRADOS
FROM BANCO_CORE.TRANSFERENCIAS T
JOIN BANCO_CATALOGO.ESTADOS_TRANSFERENCIA E
  ON E.ID_ESTADO_TRANSFERENCIA = T.ID_ESTADO_TRANSFERENCIA
LEFT JOIN BANCO_CORE.MOVIMIENTOS_CUENTA M
  ON M.ID_TRANSFERENCIA = T.ID_TRANSFERENCIA
GROUP BY T.ID_TRANSFERENCIA, E.NOMBRE_ESTADO
ORDER BY T.ID_TRANSFERENCIA DESC;

-- Bitacora: los eventos ROLLBACK_TO_* sobrevivieron gracias a la
-- transaccion autonoma. Esta es la evidencia mas fuerte del modulo.
SELECT ID_AUDITORIA, ACCION, ENTIDAD, ID_ENTIDAD, DETALLE, FECHA_HORA
FROM BANCO_CORE.AUDITORIA
WHERE ACCION LIKE 'ROLLBACK_TO%' OR ACCION LIKE 'TRANSFERENCIA%'
ORDER BY FECHA_HORA DESC;
