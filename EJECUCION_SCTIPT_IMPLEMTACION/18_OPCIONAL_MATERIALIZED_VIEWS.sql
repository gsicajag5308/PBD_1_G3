/*==============================================================================
  SCRIPT DE LIMPIEZA - Solo elimina objetos de Materialized Views
  NO toca tablas particionadas, ST, ni objetos originales
==============================================================================*/
ALTER SESSION SET "_ORACLE_SCRIPT" = true;
SET SERVEROUTPUT ON SIZE UNLIMITED;

PROMPT === Iniciando limpieza de Materialized Views ===

--==============================================================================
-- 1. Eliminar PROCEDIMIENTO
--==============================================================================
BEGIN
  EXECUTE IMMEDIATE 'DROP PROCEDURE BANCO_CORE.PRC_REFRESCAR_MVS';
  DBMS_OUTPUT.PUT_LINE('Procedimiento eliminado: PRC_REFRESCAR_MVS');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('PRC_REFRESCAR_MVS no existía o ya fue eliminado');
END;
/

--==============================================================================
-- 2. Eliminar ÍNDICES de las MVs (por si quedaron)
--==============================================================================
BEGIN
  FOR r IN (
    SELECT INDEX_NAME
    FROM DBA_INDEXES
    WHERE OWNER = 'BANCO_CORE'
      AND INDEX_NAME IN (
        'IDX_MV_RESUMEN_FECHA',
        'IDX_MV_RESUMEN_ALERTA',
        'IDX_MV_ACT_CUENTA'
      )
  ) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP INDEX BANCO_CORE.' || r.INDEX_NAME;
      DBMS_OUTPUT.PUT_LINE('Índice eliminado: ' || r.INDEX_NAME);
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('No se pudo eliminar índice ' || r.INDEX_NAME || ': ' || SQLERRM);
    END;
  END LOOP;
END;
/

--==============================================================================
-- 3. Eliminar MATERIALIZED VIEWS
--==============================================================================
BEGIN
  EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW BANCO_CORE.MV_RESUMEN_TRANSFERENCIAS';
  DBMS_OUTPUT.PUT_LINE('Materialized View eliminada: MV_RESUMEN_TRANSFERENCIAS');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('MV_RESUMEN_TRANSFERENCIAS no existía o ya fue eliminada');
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW BANCO_CORE.MV_ACTIVIDAD_CUENTAS';
  DBMS_OUTPUT.PUT_LINE('Materialized View eliminada: MV_ACTIVIDAD_CUENTAS');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('MV_ACTIVIDAD_CUENTAS no existía o ya fue eliminada');
END;
/

--==============================================================================
-- 4. Verificación final
--==============================================================================
PROMPT === Verificación: objetos restantes del módulo de MVs ===

SELECT 'MATERIALIZED VIEWS' AS TIPO, COUNT(*) AS CANTIDAD
FROM ALL_MVIEWS
WHERE OWNER = 'BANCO_CORE'
  AND MVIEW_NAME IN ('MV_RESUMEN_TRANSFERENCIAS', 'MV_ACTIVIDAD_CUENTAS')
UNION ALL
SELECT 'PROCEDIMIENTOS', COUNT(*)
FROM DBA_OBJECTS
WHERE OWNER = 'BANCO_CORE'
  AND OBJECT_TYPE = 'PROCEDURE'
  AND OBJECT_NAME = 'PRC_REFRESCAR_MVS'
UNION ALL
SELECT 'ÍNDICES', COUNT(*)
FROM DBA_INDEXES
WHERE OWNER = 'BANCO_CORE'
  AND INDEX_NAME IN (
    'IDX_MV_RESUMEN_FECHA',
    'IDX_MV_RESUMEN_ALERTA',
    'IDX_MV_ACT_CUENTA'
  );

PROMPT === Limpieza de Materialized Views finalizada ===