-- PRUEBA DE DURABILIDAD
-- Archivo: 26_PRUEBA_DURABILIDAD.sql
-- Conexion: BANCO_CORE_PROYECTO, usuario BANCO_CORE.
-- Comprueba que los saldos confirmados permanecen al reconectar.
-- Utiliza la transferencia ya realizada; no ejecuta otra.

-- PASO 1: Ejecutar la consulta con Ctrl + Enter.
-- Registrar el identificador de sesion y los saldos.

-- PASO 2: Guardar y cerrar este archivo en SQL Developer.
-- En el panel Conexiones, desconectar BANCO_CORE_PROYECTO
-- y conectar nuevamente.

-- PASO 3: Abrir este mismo archivo con BANCO_CORE_PROYECTO.
-- Ejecutar otra vez la consulta con Ctrl + Enter.
-- El identificador de sesion debe cambiar y los saldos conservarse.

SELECT DBMS_SESSION.UNIQUE_SESSION_ID AS ID_SESION,
       NUMERO_CUENTA,
       SALDO
FROM BANCO_CORE.CUENTAS
WHERE NUMERO_CUENTA IN ('001-0001', '001-0002')
ORDER BY NUMERO_CUENTA;

-- Resultado observado:
-- Sesion inicial: 020FEF2F0001.
-- Sesion posterior: 020FB26E0001.
-- Ambas consultas mostraron Q14800 y Q4200.
-- Los cambios confirmados permanecieron disponibles en la nueva sesion.
-- Esta prueba verifica persistencia ante reconexion del cliente.
-- No incluye reinicio ni caida de la base de datos.