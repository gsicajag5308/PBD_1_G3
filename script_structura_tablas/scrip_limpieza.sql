/*==============================================================================
  SISTEMA BANCARIO DE TRANSFERENCIAS - ORACLE XE 21c
  SCRIPT DE LIMPIEZA TOTAL

==============================================================================*/


--==============================================================================
-- PASO 1: Borrar usuarios de aplicación
--==============================================================================

DROP USER USR_ADMIN_BANCO CASCADE;
DROP USER USR_OPERADOR1   CASCADE;
DROP USER USR_CONSULTA1   CASCADE;


--==============================================================================
-- PASO 2: Borrar roles
--==============================================================================

DROP ROLE ROL_ADMIN_BANCO;
DROP ROLE ROL_OPERADOR_TRANSFERENCIAS;
DROP ROLE ROL_CONSULTA_BANCO;


--==============================================================================
-- PASO 3: Borrar esquema transaccional (primero, por las FK hacia catálogo)
--==============================================================================

DROP USER BANCO_CORE CASCADE;


--==============================================================================
-- PASO 4: Borrar esquema de catálogo
--==============================================================================

DROP USER BANCO_CATALOGO CASCADE;


--==============================================================================
-- PASO 5: Vaciar la papelera de reciclaje (opcional pero recomendado)
--==============================================================================
-- Oracle no borra físicamente los objetos al hacer DROP; los mueve a la
-- recyclebin. Esto libera el espacio de verdad, útil si vas a recrear todo
-- desde cero varias veces durante las pruebas del proyecto.

PURGE RECYCLEBIN;


--==============================================================================
-- PASO 6: Verificación (todo debe salir vacío / sin filas)
--==============================================================================

-- No deben aparecer los usuarios
SELECT USERNAME FROM DBA_USERS
WHERE USERNAME IN (
    'BANCO_CATALOGO', 'BANCO_CORE',
    'USR_ADMIN_BANCO', 'USR_OPERADOR1', 'USR_CONSULTA1'
);

-- No deben aparecer los roles
SELECT ROLE FROM DBA_ROLES
WHERE ROLE IN (
    'ROL_ADMIN_BANCO', 'ROL_OPERADOR_TRANSFERENCIAS', 'ROL_CONSULTA_BANCO'
);

-- No debe quedar ninguna tabla de los esquemas borrados
SELECT OWNER, TABLE_NAME FROM DBA_TABLES
WHERE OWNER IN ('BANCO_CATALOGO', 'BANCO_CORE');
