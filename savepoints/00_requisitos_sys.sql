/*==============================================================================
  PROYECTO: MODULO DE TRANSFERENCIAS INTERCUENTAS - ORACLE XE 21c
  REQUISITO 5: USO ESTRATEGICO DE SAVEPOINTS PARA RECUPERACION PARCIAL
  ESQUEMAS: BANCO_CORE (transaccional) / BANCO_CATALOGO (catalogos)
==============================================================================*/

/*  ARCHIVO 00 - EJECUTAR CONECTADO COMO SYS o SYSTEM (AS SYSDBA)
    Otorga los privilegios que el modulo necesita y agrega el estado PARCIAL
    al catalogo. Se ejecuta UNA sola vez.                                    */

ALTER SESSION SET "_ORACLE_SCRIPT" = TRUE;

-- 0.1 BANCO_CORE necesita leer los catalogos y crear tipos de objeto.
GRANT SELECT ON BANCO_CATALOGO.ESTADOS_TRANSFERENCIA TO BANCO_CORE;
GRANT SELECT ON BANCO_CATALOGO.TIPOS_MOVIMIENTO      TO BANCO_CORE;
GRANT CREATE TYPE      TO BANCO_CORE;
GRANT CREATE PROCEDURE TO BANCO_CORE;

-- 0.2 Estados de transferencia.
--     Tu proyecto_v1.sql ya carga PENDIENTE, COMPLETADA, CANCELADA y RECHAZADA.
--     Este modulo solo agrega PARCIAL, que es el estado propio de la
--     recuperacion parcial y no existia en el catalogo original.
INSERT INTO BANCO_CATALOGO.ESTADOS_TRANSFERENCIA (NOMBRE_ESTADO, DESCRIPCION)
SELECT 'PARCIAL', 'Saldos aplicados pero el registro historico fue revertido con ROLLBACK TO SAVEPOINT'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM BANCO_CATALOGO.ESTADOS_TRANSFERENCIA
                  WHERE UPPER(NOMBRE_ESTADO) = 'PARCIAL');

-- 0.3 Tipos de movimiento (ya existen en proyecto_v1.sql; el INSERT no duplica).
INSERT INTO BANCO_CATALOGO.TIPOS_MOVIMIENTO (NOMBRE_TIPO, DESCRIPCION)
SELECT 'DEBITO', 'Cargo a la cuenta'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM BANCO_CATALOGO.TIPOS_MOVIMIENTO
                  WHERE UPPER(NOMBRE_TIPO) = 'DEBITO');

INSERT INTO BANCO_CATALOGO.TIPOS_MOVIMIENTO (NOMBRE_TIPO, DESCRIPCION)
SELECT 'CREDITO', 'Abono a la cuenta'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM BANCO_CATALOGO.TIPOS_MOVIMIENTO
                  WHERE UPPER(NOMBRE_TIPO) = 'CREDITO');

COMMIT;

-- 0.4 Verificacion
SELECT ID_ESTADO_TRANSFERENCIA, NOMBRE_ESTADO FROM BANCO_CATALOGO.ESTADOS_TRANSFERENCIA;
SELECT ID_TIPO_MOVIMIENTO, NOMBRE_TIPO FROM BANCO_CATALOGO.TIPOS_MOVIMIENTO;

/*  Terminado este archivo, continuar con 01_objetos_banco_core.sql
    conectado como BANCO_CORE.                                               */
