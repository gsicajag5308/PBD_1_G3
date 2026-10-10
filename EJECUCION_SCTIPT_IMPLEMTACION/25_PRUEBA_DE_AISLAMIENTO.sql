-- PRUEBA DE AISLAMIENTO: SESION A
-- Conexion: BANCO_CORE_PROYECTO, usuario BANCO_CORE.
-- Ejecutar cada paso por separado.
-- La sesion B ejecuta la transferencia desde SQL*Plus.


-- PASO 1: Identificar la sesion y consultar los saldos iniciales.

SELECT SYS_CONTEXT('USERENV', 'SID') AS SID_A
FROM DUAL;

SELECT NUMERO_CUENTA, SALDO
FROM BANCO_CORE.CUENTAS
WHERE NUMERO_CUENTA IN ('001-0001', '001-0002')
ORDER BY NUMERO_CUENTA;


-- PASO 2: Bloquear la cuenta origen sin modificar su saldo.
-- Ejecutar este bloque con F5.
-- Mantener el bloqueo mientras la sesion B intenta transferir Q100.

SET AUTOCOMMIT OFF

SELECT NUMERO_CUENTA, SALDO
FROM BANCO_CORE.CUENTAS
WHERE NUMERO_CUENTA = '001-0001'
FOR UPDATE;


-- PASO 3: Liberar el bloqueo cuando la sesion B este esperando.
-- Ejecutar solamente esta sentencia.
-- La sesion A no modifico saldos; ROLLBACK libera el bloqueo.

ROLLBACK;


-- PASO 4: Consultar los saldos cuando la sesion B termine.
-- En la prueba realizada quedaron Q14800 y Q4200.
-- El total entre ambas cuentas se mantuvo en Q19000.

SELECT NUMERO_CUENTA, SALDO
FROM BANCO_CORE.CUENTAS
WHERE NUMERO_CUENTA IN ('001-0001', '001-0002')
ORDER BY NUMERO_CUENTA;

-- Resultado: la transferencia de la sesion B espero
-- hasta que la sesion A libero la cuenta origen.

-- PRUEBA DE AISLAMIENTO: SESION B
-- Ejecutar en SQL*Plus desde la terminal.
-- La sesion A debe mantener bloqueada la cuenta 001-0001.

-- PASO 1: Conectarse como BANCO_CORE.
-- Si ya esta conectado, omitir esta instruccion.

CONNECT BANCO_CORE/4009@192.168.1.216:1521/xe


-- PASO 2: Identificar la sesion B.
-- Su SID debe ser diferente al de la sesion A.

SELECT SYS_CONTEXT('USERENV', 'SID') AS SID_B
FROM DUAL;


-- PASO 3: Transferir Q100 entre las cuentas.
-- Pegar el bloque completo.
-- Escribir / en una linea separada y pulsar Enter para ejecutarlo.

DECLARE
    v_origen        NUMBER;
    v_destino       NUMBER;
    v_usuario       NUMBER;
    v_transferencia NUMBER;
BEGIN
    SELECT ID_CUENTA INTO v_origen
    FROM BANCO_CORE.CUENTAS
    WHERE NUMERO_CUENTA = '001-0001';
    SELECT ID_CUENTA INTO v_destino
    FROM BANCO_CORE.CUENTAS
    WHERE NUMERO_CUENTA = '001-0002';
    SELECT ID_USUARIO INTO v_usuario
    FROM BANCO_CORE.USUARIOS_SISTEMA
    WHERE NOMBRE_USUARIO = 'operador1';
    BANCO_CORE.REALIZAR_TRANSFERENCIA(
        v_origen, v_destino, 100, v_usuario, v_transferencia
    );
END;
/

-- La transferencia espera mientras la sesion A mantiene el bloqueo.
-- En SQL Developer, ejecutar ROLLBACK en la sesion A.
-- Despues, esta sesion termina la transferencia.
-- REALIZAR_TRANSFERENCIA realiza COMMIT al finalizar correctamente.


-- PASO 4: Consultar los saldos finales.
-- Ejecutar cuando vuelva a aparecer SQL>.

SELECT NUMERO_CUENTA, SALDO
FROM BANCO_CORE.CUENTAS
WHERE NUMERO_CUENTA IN ('001-0001', '001-0002')
ORDER BY NUMERO_CUENTA;

-- Resultado observado: Q14800 y Q4200.
-- El total se conservo en Q19000.
