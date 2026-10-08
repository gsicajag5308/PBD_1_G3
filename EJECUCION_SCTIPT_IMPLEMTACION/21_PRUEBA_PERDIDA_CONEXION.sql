-- PRUEBA DE PERDIDA DE CONEXION
-- Conexion: BANCO_CORE_PROYECTO, en SQL Developer.
-- Ejecutar cada paso por separado. No ejecutar todo el archivo.
-- Se deja un debito pendiente para representar una transferencia interrumpida.
-- No se llama a REALIZAR_TRANSFERENCIA, que hace COMMIT al finalizar.

-- PASO 1: Seleccionar este bloque y ejecutar con F5.
-- Usar una sesion de prueba sin otros cambios pendientes.
SET AUTOCOMMIT OFF

SELECT SYS_CONTEXT('USERENV', 'SID') AS SID FROM DUAL;

SELECT NUMERO_CUENTA, SALDO
FROM BANCO_CORE.CUENTAS
WHERE NUMERO_CUENTA IN ('001-0001', '001-0002')
ORDER BY NUMERO_CUENTA;

-- Anotar el SID y guardar los saldos iniciales.
-- En el archivo 22, ejecutar el paso 1 antes de cortar la red.

-- PASO 2: Seleccionar este bloque y ejecutar con F5 UNA SOLA VEZ.
-- La cuenta debe tener al menos Q100. No hacer COMMIT ni ROLLBACK.
UPDATE BANCO_CORE.CUENTAS
SET SALDO = SALDO - 100
WHERE NUMERO_CUENTA = '001-0001';

SELECT NUMERO_CUENTA, SALDO
FROM BANCO_CORE.CUENTAS
WHERE NUMERO_CUENTA IN ('001-0001', '001-0002')
ORDER BY NUMERO_CUENTA;

-- Guardar captura del debito pendiente.
-- VirtualBox: Configuracion de la VM > Red > Adaptador 1 > Avanzadas.
-- Desmarcar "Cable conectado" y aceptar. Mantener la VM encendida.

-- PASO 3: Con la red cortada, seleccionar solo este SELECT: Ctrl + Enter.
-- Puede quedar esperando o mostrar error. No repetir el UPDATE.
SELECT 1 FROM DUAL;

-- Revisar la transaccion desde la terminal local: paso 2 del archivo 22.
-- Restaurar "Cable conectado" en VirtualBox y aceptar.
-- Permitir que SQL Developer reconecte; guardar el aviso si aparece.
-- Si sigue esperando, cancelar la consulta y reconectar desde SQL Developer.

-- PASO 4: Con la red restaurada, revisar y recuperar la sesion antigua
-- siguiendo el paso 3 del archivo 22, en SYS_PROYECTO_BANCO.

-- PASO 5: Volver a BANCO_CORE_PROYECTO. Solo este SELECT: Ctrl + Enter.
SELECT NUMERO_CUENTA, SALDO
FROM BANCO_CORE.CUENTAS
WHERE NUMERO_CUENTA IN ('001-0001', '001-0002')
ORDER BY NUMERO_CUENTA;

-- Comparar con los saldos iniciales y guardar captura final.
-- Resultado observado el 07/10/2026:
-- Iniciales: Q15000 / Q4000.
-- El UPDATE se ejecuto dos veces por accidente: Q14800 / Q4000 pendientes.
-- El corte de red dejo la sesion antigua con transaccion pendiente.
-- La reconexion mostraba Q15000 / Q4000 porque solo veia datos confirmados.
-- Fue necesario terminar la sesion antigua desde SYS.
-- Tras recuperarla: sesion ausente y saldos Q15000 / Q4000.
-- Conclusion: perdida de conexion con recuperacion administrativa manual.
-- No se demostro reversion automatica inmediata por el corte de red.
