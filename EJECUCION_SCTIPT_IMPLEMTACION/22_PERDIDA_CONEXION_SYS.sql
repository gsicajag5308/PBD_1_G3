-- REVISION Y RECUPERACION DE LA SESION DE PRUEBA
-- SQL Developer: conexion SYS_PROYECTO_BANCO.
-- Solo durante el corte: SQL*Plus local en la terminal de la VM.
-- Ejecutar por pasos. No ejecutar todo el archivo.
-- Sustituir los valores solicitados por los de la prueba actual.

-- PASO 1: Antes del corte, en SYS_PROYECTO_BANCO (F5).
SET DEFINE ON
UNDEFINE sid_prueba
UNDEFINE serial_prueba

SELECT SID, SERIAL#, USERNAME, STATUS, TADDR
FROM V$SESSION
WHERE SID = &sid_prueba
  AND USERNAME = 'BANCO_CORE';

-- Anotar SID y SERIAL#. Corresponden a la sesion del archivo 21.
-- INACTIVE no significa que la transaccion este confirmada.

-- PASO 2: Solo mientras la red esta desconectada.
-- Abrir Terminal dentro de la VM como usuario oracle.
-- Escribir: sqlplus / as sysdba
-- Cuando aparezca SQL>, escribir la consulta siguiente cambiando 0 por el SID.
-- Esta es la unica comprobacion que necesita la terminal local.
SELECT SID, SERIAL#, TADDR FROM V$SESSION WHERE SID = 0;

-- TADDR con valor indica una transaccion asociada a la sesion.
-- Guardar captura. Restaurar el cable de red en VirtualBox.
-- Continuar en SQL Developer, conexion SYS_PROYECTO_BANCO.

-- PASO 3: Consultar de nuevo la sesion antigua (seleccionar y F5).
SELECT SID, SERIAL#, USERNAME, STATUS, TADDR
FROM V$SESSION
WHERE SID = &sid_prueba
  AND USERNAME = 'BANCO_CORE';

-- Si no hay filas, o TADDR esta vacio, no ejecutar el KILL.
-- Si sigue pendiente, verificar que SID y SERIAL# sean los anotados
-- en el paso 1. Terminar SOLO esa sesion de prueba (seleccionar y F5).
ALTER SYSTEM KILL SESSION '&sid_prueba,&serial_prueba' IMMEDIATE;

-- PASO 4: Verificar la sesion (seleccionar y F5).
SELECT SID, SERIAL#, STATUS, TADDR
FROM V$SESSION
WHERE SID = &sid_prueba;

-- Se espera ninguna fila o TADDR vacio para la sesion terminada.
-- Si la recuperacion sigue pendiente, repetir solamente esta consulta.
-- Guardar captura y volver al paso 5 del archivo 21 para comprobar saldos.

-- Evidencia del 07/10/2026:
-- Sesion de prueba: SID 547, SERIAL# 39303.
-- TADDR tenia valor durante el corte y despues de reconectar.
-- KILL SESSION termino correctamente; luego no se encontraron filas.
-- Los numeros anteriores son evidencia historica: NO reutilizarlos.
