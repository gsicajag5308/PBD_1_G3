/*==============================================================================
  MATERIALIZED VIEWS adaptadas al módulo de Particionamiento
  Fuente: TRANSFERENCIAS_PART (tabla particionada)
  Esquema: BANCO_CORE
==============================================================================*/
ALTER SESSION SET "_ORACLE_SCRIPT" = true;
SET SERVEROUTPUT ON;



GRANT CREATE MATERIALIZED VIEW TO BANCO_CORE;
GRANT QUERY REWRITE TO BANCO_CORE;          -- recomendado
GRANT CREATE TABLE TO BANCO_CORE;           -- por si acaso (las MVs crean tablas internas)
GRANT CREATE ANY TABLE TO BANCO_CORE;       -- a veces necesario en XE

-- Verificar
SELECT * FROM DBA_SYS_PRIVS 
WHERE GRANTEE = 'BANCO_CORE' 
  AND PRIVILEGE LIKE '%MATERIALIZED%';
-- Privilegios necesarios (ejecutar como SYS si aún no los tiene):
-- GRANT CREATE MATERIALIZED VIEW TO BANCO_CORE;
-- GRANT QUERY REWRITE TO BANCO_CORE;   -- opcional

--==============================================================================
-- Limpieza previa de MVs e índices (por si ya existen)
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
-- MV 1: Resumen diario de transferencias y nivel de alerta
--        (lee de la tabla particionada TRANSFERENCIAS_PART)
--==============================================================================
CREATE MATERIALIZED VIEW BANCO_CORE.MV_RESUMEN_TRANSFERENCIAS
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
SELECT
    T.PARTITION_DATE                    AS FECHA_DIA,          -- ya es DATE
    E.NOMBRE_ESTADO,
    CASE
        WHEN T.MONTO > 10000 THEN 'ALERTA MUY ALTA'
        WHEN T.MONTO > 5000  THEN 'ALERTA ALTA'
        WHEN T.MONTO > 3000  THEN 'REVISION'
        ELSE 'NORMAL'
    END                                 AS NIVEL_ALERTA,
    COUNT(*)                            AS CANTIDAD_TRANSFERENCIAS,
    SUM(T.MONTO)                        AS MONTO_TOTAL,
    ROUND(AVG(T.MONTO), 2)              AS MONTO_PROMEDIO,
    MAX(T.MONTO)                        AS MONTO_MAXIMO
FROM BANCO_CORE.TRANSFERENCIAS_PART T
JOIN BANCO_CATALOGO.ESTADOS_TRANSFERENCIA E
  ON E.ID_ESTADO_TRANSFERENCIA = T.ID_ESTADO_TRANSFERENCIA
GROUP BY
    T.PARTITION_DATE,
    E.NOMBRE_ESTADO,
    CASE
        WHEN T.MONTO > 10000 THEN 'ALERTA MUY ALTA'
        WHEN T.MONTO > 5000  THEN 'ALERTA ALTA'
        WHEN T.MONTO > 3000  THEN 'REVISION'
        ELSE 'NORMAL'
    END;

-- Índices sobre la MV
CREATE INDEX BANCO_CORE.IDX_MV_RESUMEN_FECHA
  ON BANCO_CORE.MV_RESUMEN_TRANSFERENCIAS (FECHA_DIA);

CREATE INDEX BANCO_CORE.IDX_MV_RESUMEN_ALERTA
  ON BANCO_CORE.MV_RESUMEN_TRANSFERENCIAS (NIVEL_ALERTA);


--==============================================================================
-- MV 2: Actividad por cuenta (origen/destino + saldo actual)
--       Usa TRANSFERENCIAS_PART + tablas maestras
--==============================================================================
CREATE MATERIALIZED VIEW BANCO_CORE.MV_ACTIVIDAD_CUENTAS
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
SELECT
    C.ID_CUENTA,
    C.NUMERO_CUENTA,
    C.SALDO,
    C.ESTADO,
    CL.ID_CLIENTE,
    CL.NOMBRES || ' ' || CL.APELLIDOS AS CLIENTE,
    NVL(SUM(CASE WHEN T.ID_CUENTA_ORIGEN  = C.ID_CUENTA THEN 1 ELSE 0 END), 0) AS CANT_ENVIADAS,
    NVL(SUM(CASE WHEN T.ID_CUENTA_DESTINO = C.ID_CUENTA THEN 1 ELSE 0 END), 0) AS CANT_RECIBIDAS,
    NVL(SUM(CASE WHEN T.ID_CUENTA_ORIGEN  = C.ID_CUENTA THEN T.MONTO ELSE 0 END), 0) AS TOTAL_ENVIADO,
    NVL(SUM(CASE WHEN T.ID_CUENTA_DESTINO = C.ID_CUENTA THEN T.MONTO ELSE 0 END), 0) AS TOTAL_RECIBIDO
FROM BANCO_CORE.CUENTAS C
JOIN BANCO_CORE.CLIENTES CL
  ON CL.ID_CLIENTE = C.ID_CLIENTE
LEFT JOIN BANCO_CORE.TRANSFERENCIAS_PART T
  ON T.ID_CUENTA_ORIGEN  = C.ID_CUENTA
  OR T.ID_CUENTA_DESTINO = C.ID_CUENTA
GROUP BY
    C.ID_CUENTA, C.NUMERO_CUENTA, C.SALDO, C.ESTADO,
    CL.ID_CLIENTE, CL.NOMBRES, CL.APELLIDOS;

CREATE INDEX BANCO_CORE.IDX_MV_ACT_CUENTA
  ON BANCO_CORE.MV_ACTIVIDAD_CUENTAS (NUMERO_CUENTA);


--==============================================================================
-- Procedimiento para refrescar las MVs después de cargar las particiones
--==============================================================================
CREATE OR REPLACE PROCEDURE BANCO_CORE.PRC_REFRESCAR_MVS AS
BEGIN
    DBMS_MVIEW.REFRESH('BANCO_CORE.MV_RESUMEN_TRANSFERENCIAS', 'C');
    DBMS_MVIEW.REFRESH('BANCO_CORE.MV_ACTIVIDAD_CUENTAS', 'C');
    DBMS_OUTPUT.PUT_LINE('Materialized Views refrescadas correctamente');
END;
/


--==============================================================================
-- Verificación
--==============================================================================
SELECT OWNER, MVIEW_NAME, REFRESH_MODE, REFRESH_METHOD, BUILD_MODE, LAST_REFRESH_DATE
FROM ALL_MVIEWS
WHERE OWNER = 'BANCO_CORE'
ORDER BY MVIEW_NAME;

-- Consultas de prueba
SELECT * FROM BANCO_CORE.MV_RESUMEN_TRANSFERENCIAS
ORDER BY FECHA_DIA DESC, NIVEL_ALERTA;

SELECT * FROM BANCO_CORE.MV_ACTIVIDAD_CUENTAS
ORDER BY TOTAL_ENVIADO DESC;