--==============================================================================
-- PRUEBA DE CAIDA DE SESION: OPERACION PENDIENTE
-- Conexion: BANCO_CORE_PROYECTO (usuario BANCO_CORE).
-- Objetivo: comprobar la reversion automatica de un debito sin COMMIT.
-- Esta prueba reproduce el punto intermedio de una transferencia; no llama
-- a REALIZAR_TRANSFERENCIA, porque ese procedimiento confirma al finalizar.
-- Ejecutar por pasos, seleccionando cada bloque. No ejecutar todo el archivo.
--==============================================================================

-- PASO 1: Consultar la sesion y registrar los saldos iniciales (F5).
-- Usar una sesion de prueba sin otras operaciones pendientes.
SET AUTOCOMMIT OFF

SELECT SYS_CONTEXT('USERENV', 'SESSION_USER') AS USUARIO,
       SYS_CONTEXT('USERENV', 'SID') AS SID
FROM DUAL;

SELECT NUMERO_CUENTA, SALDO
FROM BANCO_CORE.CUENTAS
WHERE NUMERO_CUENTA IN ('001-0001', '001-0002')
ORDER BY NUMERO_CUENTA;

-- PASO 2: Aplicar solamente el debito y consultar los saldos (F5).
-- Ejecutar este bloque una sola vez. No ejecutar COMMIT ni ROLLBACK.
-- La cuenta origen debe estar activa y tener al menos Q100.
UPDATE BANCO_CORE.CUENTAS
SET SALDO = SALDO - 100
WHERE NUMERO_CUENTA = '001-0001';

SELECT NUMERO_CUENTA, SALDO
FROM BANCO_CORE.CUENTAS
WHERE NUMERO_CUENTA IN ('001-0001', '001-0002')
ORDER BY NUMERO_CUENTA;

-- DETENERSE AQUI. Dejar esta hoja abierta.
-- Guardar captura del debito pendiente y continuar con 20_CAIDA_SESION_SYS.sql
-- en otra hoja con conexion SYS_PROYECTO_BANCO.

-- PASO 3: Solo despues de terminar la sesion desde el archivo 20.
-- Ejecutar exclusivamente este SELECT con Ctrl + Enter.
-- SQL Developer puede mostrar un error o restablecer la conexion.
-- Guardar captura del aviso de reconexion y aceptar si aparece.
SELECT 1 FROM DUAL;

-- PASO 4: Tras reconectar, verificar los saldos con Ctrl + Enter.
-- Deben coincidir con los registrados en el paso 1.
SELECT NUMERO_CUENTA, SALDO
FROM BANCO_CORE.CUENTAS
WHERE NUMERO_CUENTA IN ('001-0001', '001-0002')
ORDER BY NUMERO_CUENTA;

-- Evidencia obtenida el 07/10/2026:
-- Inicial: Q15000 y Q4000. Pendiente: Q14900 y Q4000.
-- Despues de la caida: Q15000 y Q4000, sin ROLLBACK manual.
-- Demuestra recuperacion de una transaccion no confirmada (atomicidad).
-- No demuestra por si sola todas las propiedades ACID ni un corte de red.