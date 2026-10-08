--==============================================================================
-- PRUEBA DE CAIDA DE SESION: TERMINACION Y VERIFICACION
-- Conexion: SYS_PROYECTO_BANCO (SYS con rol SYSDBA).
-- Requisito: completar pasos 1 y 2 del archivo 19 y dejar esa hoja abierta.
-- Ejecutar por pasos. SID y SERIAL# cambian en cada prueba.
--==============================================================================

-- PASO 1: Consultar la sesion de prueba (F5).
-- Al solicitar sid_prueba, introducir el SID mostrado en el archivo 19.
-- Confirmar que USERNAME es BANCO_CORE y anotar SERIAL#.
SET DEFINE ON
UNDEFINE sid_prueba
UNDEFINE serial_prueba

SELECT SID, SERIAL#, USERNAME, STATUS
FROM V$SESSION
WHERE SID = &sid_prueba
  AND USERNAME = 'BANCO_CORE';

-- DETENERSE y revisar el resultado antes de continuar.
-- INACTIVE significa que la sesion no ejecuta una sentencia en ese instante;
-- no significa que haya confirmado su transaccion.

-- PASO 2: Terminar solamente la sesion identificada (F5).
-- Seleccionar exclusivamente la sentencia siguiente.
-- Introducir serial_prueba con el SERIAL# obtenido en el paso 1.
-- No utilizar valores de una prueba anterior ni de otra sesion.
ALTER SYSTEM KILL SESSION '&sid_prueba,&serial_prueba' IMMEDIATE;

-- PASO 3: Verificar la recuperacion de saldos (Ctrl + Enter).
-- Comparar con la captura inicial del archivo 19.
-- Si Oracle sigue recuperando la transaccion, repetir solo esta consulta.
SELECT NUMERO_CUENTA, SALDO
FROM BANCO_CORE.CUENTAS
WHERE NUMERO_CUENTA IN ('001-0001', '001-0002')
ORDER BY NUMERO_CUENTA;

-- Guardar captura de los saldos restaurados.
-- Volver al archivo 19 para ejecutar sus pasos 3 y 4.
-- Oracle revierte los cambios sin COMMIT de la sesion terminada.
-- En nuestra prueba los saldos restaurados fueron Q15000 y Q4000.
