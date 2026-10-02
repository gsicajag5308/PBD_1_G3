/*==============================================================================
  LIMPIEZA GLOBAL COMPLETA - DEJA TODO COMO DE CERO
  Ejecutar como SYS o SYSTEM
  - Elimina triggers, procedimientos, funciones, tipos, FGA, índices, MVs
  - Trunca tablas operativas
  - Reinicia todos los IDENTITY a 1
  - Conserva la columna DESCRIPCION de TRANSFERENCIAS
==============================================================================*/
ALTER SESSION SET "_ORACLE_SCRIPT" = true;
SET SERVEROUTPUT ON SIZE UNLIMITED;

--  ========================================================
--   INICIO LIMPIEZA GLOBAL - TODO QUEDA EN CERO
--  ========================================================

--==============================================================================
-- 1. ELIMINAR TODOS LOS TRIGGERS
--==============================================================================
BEGIN
  FOR r IN (SELECT OWNER, TRIGGER_NAME FROM DBA_TRIGGERS WHERE OWNER = 'BANCO_CORE') LOOP
    BEGIN
      EXECUTE IMMEDIATE 'ALTER TRIGGER ' || r.OWNER || '.' || r.TRIGGER_NAME || ' DISABLE';
      EXECUTE IMMEDIATE 'DROP TRIGGER ' || r.OWNER || '.' || r.TRIGGER_NAME;
      DBMS_OUTPUT.PUT_LINE('Trigger eliminado: ' || r.TRIGGER_NAME);
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Error eliminando trigger ' || r.TRIGGER_NAME || ': ' || SQLERRM);
    END;
  END LOOP;
END;
/

--==============================================================================
-- 2. ELIMINAR PROCEDIMIENTOS Y FUNCIONES
--==============================================================================
BEGIN
  FOR r IN (
    SELECT OBJECT_NAME, OBJECT_TYPE
    FROM DBA_OBJECTS
    WHERE OWNER = 'BANCO_CORE'
      AND OBJECT_TYPE IN ('PROCEDURE','FUNCTION')
      AND OBJECT_NAME IN (
        'PRC_TRANSFERENCIA_SP',
        'PRC_LOTE_TRANSFERENCIAS',
        'PRC_LOG_AUDITORIA',
        'FN_ID_ESTADO_TRANSF',
        'FN_ID_TIPO_MOV',
        'REALIZAR_TRANSFERENCIA',
        'PRC_TRANSFERENCIA_TIMESTAMP',
        'PRC_CARGAR_ST',
        'PRC_CARGAR_PARTICIONADAS',
        'PRC_REFRESCAR_PARTICIONES',
        'PRC_REFRESCAR_MVS'
      )
  ) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP ' || r.OBJECT_TYPE || ' BANCO_CORE.' || r.OBJECT_NAME;
      DBMS_OUTPUT.PUT_LINE(r.OBJECT_TYPE || ' eliminado: ' || r.OBJECT_NAME);
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Error eliminando ' || r.OBJECT_NAME || ': ' || SQLERRM);
    END;
  END LOOP;
END;
/

--==============================================================================
-- 3. ELIMINAR TIPOS
--==============================================================================
BEGIN
  EXECUTE IMMEDIATE 'DROP TYPE BANCO_CORE.T_LOTE_TRANSFERENCIAS FORCE';
  DBMS_OUTPUT.PUT_LINE('Tipo T_LOTE_TRANSFERENCIAS eliminado');
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP TYPE BANCO_CORE.T_TRANSFERENCIA_ITEM FORCE';
  DBMS_OUTPUT.PUT_LINE('Tipo T_TRANSFERENCIA_ITEM eliminado');
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

--==============================================================================
-- 4. ELIMINAR MATERIALIZED VIEWS
--==============================================================================
BEGIN
  EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW BANCO_CORE.MV_RESUMEN_TRANSFERENCIAS';
  DBMS_OUTPUT.PUT_LINE('MV_RESUMEN_TRANSFERENCIAS eliminada');
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW BANCO_CORE.MV_ACTIVIDAD_CUENTAS';
  DBMS_OUTPUT.PUT_LINE('MV_ACTIVIDAD_CUENTAS eliminada');
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

--==============================================================================
-- 5. ELIMINAR ÍNDICES
--==============================================================================
BEGIN
  FOR r IN (
    SELECT INDEX_NAME
    FROM DBA_INDEXES
    WHERE OWNER = 'BANCO_CORE'
      AND INDEX_NAME IN (
        'IDX_TRANS_MONTO','IDX_TRANS_FECHA','IDX_TRANS_USUARIO',
        'IDX_TRANS_ORIGEN','IDX_TRANS_DESTINO','IDX_MOV_CUENTA_FECHA',
        'IDX_TP_MONTO','IDX_TP_FECHA','IDX_TP_ORIGEN','IDX_TP_DESTINO',
        'IDX_MP_CUENTA_FECHA','IDX_MP_PDATE',
        'IDX_MV_RESUMEN_FECHA','IDX_MV_RESUMEN_ALERTA','IDX_MV_ACT_CUENTA'
      )
  ) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP INDEX BANCO_CORE.' || r.INDEX_NAME;
      DBMS_OUTPUT.PUT_LINE('Índice eliminado: ' || r.INDEX_NAME);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END;
/

--==============================================================================
-- 6. ELIMINAR TABLAS DE STAGING Y PARTICIONADAS
--==============================================================================
BEGIN
  FOR r IN (
    SELECT TABLE_NAME
    FROM DBA_TABLES
    WHERE OWNER = 'BANCO_CORE'
      AND TABLE_NAME IN (
        'ST_TRANSFERENCIAS','ST_MOVIMIENTOS',
        'TRANSFERENCIAS_PART','MOVIMIENTOS_PART'
      )
  ) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP TABLE BANCO_CORE.' || r.TABLE_NAME || ' PURGE';
      DBMS_OUTPUT.PUT_LINE('Tabla eliminada: ' || r.TABLE_NAME);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END;
/

--==============================================================================
-- 7. ELIMINAR POLÍTICAS FGA
--==============================================================================
BEGIN DBMS_FGA.DROP_POLICY('BANCO_CORE','CUENTAS','FGA_CUENTAS_SALDO_ALTO');        EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN DBMS_FGA.DROP_POLICY('BANCO_CORE','CUENTAS','FGA_CUENTAS_MOD_SALDO');         EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN DBMS_FGA.DROP_POLICY('BANCO_CORE','TRANSFERENCIAS','FGA_TRANSFERENCIA_MONTO_ALTO'); EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN DBMS_FGA.DROP_POLICY('BANCO_CORE','CLIENTES','FGA_CLIENTES_DATOS_SENSIBLES'); EXCEPTION WHEN OTHERS THEN NULL; END;
/
DBMS_OUTPUT.PUT_LINE('Políticas FGA eliminadas');

--==============================================================================
-- 8. TRUNCAR TABLAS OPERATIVAS (dejarlas en blanco)
--==============================================================================
--  === Truncando tablas operativas ===

TRUNCATE TABLE BANCO_CORE.AUDITORIA;
TRUNCATE TABLE BANCO_CORE.MOVIMIENTOS_CUENTA;
TRUNCATE TABLE BANCO_CORE.TRANSFERENCIAS;          -- conserva DESCRIPCION

-- Tablas maestras (DELETE porque tienen FKs e Identity)
DELETE FROM BANCO_CORE.CUENTAS;
DELETE FROM BANCO_CORE.CLIENTES;
DELETE FROM BANCO_CORE.USUARIOS_SISTEMA;
COMMIT;

DBMS_OUTPUT.PUT_LINE('Tablas operativas truncadas / vaciadas');

--==============================================================================
-- 9. REINICIAR TODOS LOS IDENTITY A 1
--==============================================================================
--  === Reiniciando Identities a START WITH 1 ===

ALTER TABLE BANCO_CORE.USUARIOS_SISTEMA 
  MODIFY ID_USUARIO GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE);

ALTER TABLE BANCO_CORE.CLIENTES 
  MODIFY ID_CLIENTE GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE);

ALTER TABLE BANCO_CORE.CUENTAS 
  MODIFY ID_CUENTA GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE);

ALTER TABLE BANCO_CORE.TRANSFERENCIAS 
  MODIFY ID_TRANSFERENCIA GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE);

ALTER TABLE BANCO_CORE.MOVIMIENTOS_CUENTA 
  MODIFY ID_MOVIMIENTO GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE);

ALTER TABLE BANCO_CORE.AUDITORIA 
  MODIFY ID_AUDITORIA GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE);

DBMS_OUTPUT.PUT_LINE('Todos los Identity reiniciados a 1');

--==============================================================================
-- 10. VERIFICACIÓN FINAL
--==============================================================================
--  ========================================================
--   VERIFICACIÓN FINAL - TODO DEBE ESTAR EN CERO
--  ========================================================

SELECT 'TRIGGERS'              AS TIPO, COUNT(*) AS CANT FROM DBA_TRIGGERS WHERE OWNER = 'BANCO_CORE'
UNION ALL
SELECT 'PROCEDURES'            , COUNT(*) FROM DBA_OBJECTS WHERE OWNER = 'BANCO_CORE' AND OBJECT_TYPE = 'PROCEDURE'
UNION ALL
SELECT 'FUNCTIONS'             , COUNT(*) FROM DBA_OBJECTS WHERE OWNER = 'BANCO_CORE' AND OBJECT_TYPE = 'FUNCTION'
UNION ALL
SELECT 'TYPES'                 , COUNT(*) FROM DBA_OBJECTS WHERE OWNER = 'BANCO_CORE' AND OBJECT_TYPE = 'TYPE'
UNION ALL
SELECT 'MATERIALIZED VIEWS'    , COUNT(*) FROM ALL_MVIEWS WHERE OWNER = 'BANCO_CORE'
UNION ALL
SELECT 'FGA POLICIES'          , COUNT(*) FROM DBA_AUDIT_POLICIES WHERE OBJECT_SCHEMA = 'BANCO_CORE'
UNION ALL
SELECT 'TABLAS ST/PART'        , COUNT(*) FROM DBA_TABLES WHERE OWNER = 'BANCO_CORE' 
                                      AND TABLE_NAME IN ('ST_TRANSFERENCIAS','ST_MOVIMIENTOS','TRANSFERENCIAS_PART','MOVIMIENTOS_PART')
UNION ALL
SELECT 'FILAS USUARIOS'        , COUNT(*) FROM BANCO_CORE.USUARIOS_SISTEMA
UNION ALL
SELECT 'FILAS CLIENTES'        , COUNT(*) FROM BANCO_CORE.CLIENTES
UNION ALL
SELECT 'FILAS CUENTAS'         , COUNT(*) FROM BANCO_CORE.CUENTAS
UNION ALL
SELECT 'FILAS TRANSFERENCIAS'  , COUNT(*) FROM BANCO_CORE.TRANSFERENCIAS
UNION ALL
SELECT 'FILAS MOVIMIENTOS'     , COUNT(*) FROM BANCO_CORE.MOVIMIENTOS_CUENTA
UNION ALL
SELECT 'FILAS AUDITORIA'       , COUNT(*) FROM BANCO_CORE.AUDITORIA;

-- Confirmar que DESCRIPCION sigue existiendo
SELECT COLUMN_NAME, DATA_TYPE, DATA_LENGTH
FROM   DBA_TAB_COLUMNS
WHERE  OWNER = 'BANCO_CORE'
  AND  TABLE_NAME = 'TRANSFERENCIAS'
  AND  COLUMN_NAME = 'DESCRIPCION';

--  ========================================================
--   LIMPIEZA COMPLETADA - BASE LISTA PARA EMPEZAR DE CERO
--  ========================================================