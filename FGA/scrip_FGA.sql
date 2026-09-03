--==============================================================================
-- PASO 1: Permitir crear usuarios sin restricciones de contraseña
--==============================================================================

ALTER SESSION SET "_ORACLE_SCRIPT" = true;

--==============================================================================
-- PASO 2:  Verificar que el paquete DBMS_FGA está disponible
--==============================================================================

SELECT OBJECT_NAME, STATUS FROM DBA_OBJECTS WHERE OBJECT_NAME = 'DBMS_FGA' AND OWNER = 'SYS';

--==============================================================================
-- PASO 3: Otorgar privilegio de ejecución a tu usuario administrador
--==============================================================================
GRANT EXECUTE ON DBMS_FGA TO BANCO_CORE;
GRANT EXECUTE ON DBMS_FGA TO USR_ADMIN_BANCO;


--==============================================================================
-- PASO 4: Dar permisos de coneccion 
--==============================================================================
GRANT CREATE SESSION TO BANCO_CORE;

--==============================================================================
-- PASO 5: Crear politicas puede ser del usuario dba o BANCO_CORE
--==============================================================================


---Política: auditar cualquier modificación de saldo (UPDATE)
BEGIN
  DBMS_FGA.ADD_POLICY(
    object_schema   => 'BANCO_CORE',
    object_name     => 'CUENTAS',
    policy_name     => 'FGA_CUENTAS_MOD_SALDO',
    audit_condition => NULL,  -- NULL = siempre que se toque la columna
    audit_column    => 'SALDO',
    statement_types => 'UPDATE',
    enable          => TRUE
  );
END;
/
---Política básica: auditar consultas a saldos altos
BEGIN
  DBMS_FGA.ADD_POLICY(
    object_schema   => 'BANCO_CORE',
    object_name     => 'CUENTAS',
    policy_name     => 'FGA_CUENTAS_SALDO_ALTO',
    audit_condition => 'SALDO > 10000',
    audit_column    => 'SALDO',
    statement_types => 'SELECT,UPDATE',
    enable          => TRUE
  );
END;
/
-- Crear la tercera política — auditar transferencias grandes
BEGIN
  DBMS_FGA.ADD_POLICY(
    object_schema   => 'BANCO_CORE',
    object_name     => 'TRANSFERENCIAS',
    policy_name     => 'FGA_TRANSFERENCIA_MONTO_ALTO',
    audit_condition => 'MONTO > 5000',
    audit_column    => 'MONTO',
    statement_types => 'INSERT,UPDATE',
    enable          => TRUE
  );
END;
/

-- Crear la cuarta política — auditar acceso a datos sensibles de clientes

BEGIN
  DBMS_FGA.ADD_POLICY(
    object_schema   => 'BANCO_CORE',
    object_name     => 'CLIENTES',
    policy_name     => 'FGA_CLIENTES_DATOS_SENSIBLES',
    audit_column    => 'NUMERO_DOCUMENTO,CORREO',
    statement_types => 'SELECT',
    enable          => TRUE
  );
END;
/

--==============================================================================
-- PASO 5: ver politicas 
--==============================================================================
SELECT * FROM DBA_AUDIT_POLICIES;

SELECT OBJECT_NAME, POLICY_NAME, ENABLED
FROM DBA_AUDIT_POLICIES
WHERE OBJECT_SCHEMA = 'BANCO_CORE'
ORDER BY OBJECT_NAME, POLICY_NAME;


--
--==============================================================================
-- PASO 6: Probar las políticas de 
--==============================================================================
-- FGA_CUENTAS_MOD_SALDO
SELECT * FROM BANCO_CORE.CUENTAS  WHERE NUMERO_CUENTA = '001-0001';
SELECT NUMERO_CUENTA, SALDO FROM BANCO_CORE.CUENTAS WHERE NUMERO_CUENTA = '001-0001';

-- UPDATE a la columna SALDO
UPDATE BANCO_CORE.CUENTAS SET SALDO = 15000 WHERE NUMERO_CUENTA = '001-0001';
COMMIT;
-- Ver registros
SELECT DB_USER, OBJECT_SCHEMA, OBJECT_NAME, POLICY_NAME, SQL_TEXT, TIMESTAMP
FROM DBA_FGA_AUDIT_TRAIL
ORDER BY TIMESTAMP DESC;

--Probar las políticas de TRANSFERENCIAS y CLIENTE
INSERT INTO BANCO_CORE.TRANSFERENCIAS  (ID_CUENTA_ORIGEN, ID_CUENTA_DESTINO, MONTO, ID_ESTADO_TRANSFERENCIA, ID_USUARIO)
VALUES (1, 2, 7000, 2, 1);
COMMIT;
-- consultas clientes
SELECT NOMBRES, APELLIDOS, CORREO FROM BANCO_CORE.CLIENTES WHERE ID_CLIENTE = 1;

-- Ver registros
SELECT DB_USER, OBJECT_SCHEMA, OBJECT_NAME, POLICY_NAME, SQL_TEXT, TIMESTAMP
FROM DBA_FGA_AUDIT_TRAIL
ORDER BY TIMESTAMP DESC;