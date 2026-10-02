--================================================================
-----01 ACID (Atomicidad, Consistencia, Aislamiento, Durabilidad)
--================================================================
-- Usar 02_probar_acid.sql o:
-- Usar 02_probar_acid.sql o:
SET SERVEROUTPUT ON;
DECLARE
  v_o NUMBER; v_d NUMBER; v_u NUMBER; v_t NUMBER;
BEGIN
  SELECT ID_CUENTA INTO v_o FROM BANCO_CORE.CUENTAS WHERE NUMERO_CUENTA='001-0001';
  SELECT ID_CUENTA INTO v_d FROM BANCO_CORE.CUENTAS WHERE NUMERO_CUENTA='001-0002';
  SELECT ID_USUARIO INTO v_u FROM BANCO_CORE.USUARIOS_SISTEMA WHERE NOMBRE_USUARIO='USR_OPERADOR1';
  BANCO_CORE.REALIZAR_TRANSFERENCIA(v_o, v_d, 100, v_u, v_t);
  DBMS_OUTPUT.PUT_LINE('Transferencia ID='||v_t);
END;
/
SELECT NUMERO_CUENTA, SALDO FROM BANCO_CORE.CUENTAS WHERE NUMERO_CUENTA IN ('001-0001','001-0002');
-- Simular fallo: forzar sobregiro y verificar ROLLBACK total
-- Simular fallo: forzar sobregiro y verificar ROLLBACK total