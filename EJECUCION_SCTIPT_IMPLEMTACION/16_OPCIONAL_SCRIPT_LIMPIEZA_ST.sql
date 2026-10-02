/*==============================================================================
  SCRIPT DE LIMPIEZA - Solo elimina objetos del módulo de Particionamiento
  (ST + tablas particionadas + índices + procedimientos)
  NO toca: TRANSFERENCIAS, MOVIMIENTOS_CUENTA ni ningún otro objeto original
==============================================================================*/
ALTER SESSION SET "_ORACLE_SCRIPT" = true;
SET SERVEROUTPUT ON SIZE UNLIMITED;

PROMPT === Iniciando limpieza del módulo de Particionamiento ===

--==============================================================================
-- 1. Eliminar PROCEDIMIENTOS
--==============================================================================
BEGIN
  FOR r IN (
    SELECT OBJECT_NAME
    FROM DBA_OBJECTS
    WHERE OWNER = 'BANCO_CORE'
      AND OBJECT_TYPE = 'PROCEDURE'
      AND OBJECT_NAME IN (
        'PRC_CARGAR_ST',
        'PRC_CARGAR_PARTICIONADAS',
        'PRC_REFRESCAR_PARTICIONES'
      )
  ) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP PROCEDURE BANCO_CORE.' || r.OBJECT_NAME;
      DBMS_OUTPUT.PUT_LINE('Procedimiento eliminado: ' || r.OBJECT_NAME);
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('No se pudo eliminar procedimiento ' || r.OBJECT_NAME || ': ' || SQLERRM);
    END;
  END LOOP;
END;
/

--==============================================================================
-- 2. Eliminar ÍNDICES (por si quedaron huérfanos)
--==============================================================================
BEGIN
  FOR r IN (
    SELECT INDEX_NAME
    FROM DBA_INDEXES
    WHERE OWNER = 'BANCO_CORE'
      AND INDEX_NAME IN (
        'IDX_TP_MONTO',
        'IDX_TP_FECHA',
        'IDX_TP_ORIGEN',
        'IDX_TP_DESTINO',
        'IDX_MP_CUENTA_FECHA',
        'IDX_MP_PDATE'
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
-- 3. Eliminar TABLAS (ST + Particionadas)
--==============================================================================
BEGIN
  FOR r IN (
    SELECT TABLE_NAME
    FROM DBA_TABLES
    WHERE OWNER = 'BANCO_CORE'
      AND TABLE_NAME IN (
        'ST_TRANSFERENCIAS',
        'ST_MOVIMIENTOS',
        'TRANSFERENCIAS_PART',
        'MOVIMIENTOS_PART'
      )
  ) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP TABLE BANCO_CORE.' || r.TABLE_NAME || ' PURGE';
      DBMS_OUTPUT.PUT_LINE('Tabla eliminada: ' || r.TABLE_NAME);
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('No se pudo eliminar tabla ' || r.TABLE_NAME || ': ' || SQLERRM);
    END;
  END LOOP;
END;
/

--==============================================================================
-- 4. Verificación final
--==============================================================================
PROMPT === Verificación: objetos restantes del módulo ===

SELECT 'PROCEDIMIENTOS' AS TIPO, COUNT(*) AS CANTIDAD
FROM DBA_OBJECTS
WHERE OWNER = 'BANCO_CORE'
  AND OBJECT_TYPE = 'PROCEDURE'
  AND OBJECT_NAME IN ('PRC_CARGAR_ST','PRC_CARGAR_PARTICIONADAS','PRC_REFRESCAR_PARTICIONES')
UNION ALL
SELECT 'TABLAS', COUNT(*)
FROM DBA_TABLES
WHERE OWNER = 'BANCO_CORE'
  AND TABLE_NAME IN ('ST_TRANSFERENCIAS','ST_MOVIMIENTOS','TRANSFERENCIAS_PART','MOVIMIENTOS_PART')
UNION ALL
SELECT 'ÍNDICES', COUNT(*)
FROM DBA_INDEXES
WHERE OWNER = 'BANCO_CORE'
  AND INDEX_NAME IN (
    'IDX_TP_MONTO','IDX_TP_FECHA','IDX_TP_ORIGEN','IDX_TP_DESTINO',
    'IDX_MP_CUENTA_FECHA','IDX_MP_PDATE'
  );

PROMPT === Limpieza del módulo de Particionamiento finalizada ===