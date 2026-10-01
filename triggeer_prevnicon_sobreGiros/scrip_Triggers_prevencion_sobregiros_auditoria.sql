--==============================================================================
-- TRIGGERS RECOMENDADOS PARA EL MÓDULO BANCARIO
-- Esquema: BANCO_CORE
-- Objetivo:
--   1. Prevenir sobregiros (saldo negativo)
--   2. Auditar automáticamente cualquier cambio de saldo
--   3. Cumplir con el requisito de "Triggers compuestos"
--==============================================================================

ALTER SESSION SET "_ORACLE_SCRIPT" = true;
--==============================================================================
-- TRIGGER 1: PREVENCIÓN DE SOBREGIRO ANTES DE LA FILA (BEFORE ROW)
--==============================================================================
/*
  Tipo          : BEFORE UPDATE OF SALDO ... FOR EACH ROW
  Cuándo se dispara: Solo cuando se modifica la columna SALDO
  Qué hace      : Rechaza la operación si el nuevo saldo sería negativo
  Código error  : ORA-20001 (rango de aplicación -20000 a -20999)
  Nota          : Si este trigger lanza error, el COMPOUND nunca se ejecuta
*/

CREATE OR REPLACE TRIGGER BANCO_CORE.TRG_PREVENIR_SOBREGIRO
BEFORE UPDATE OF SALDO ON BANCO_CORE.CUENTAS
FOR EACH ROW
BEGIN
    IF :NEW.SALDO < 0 THEN
        RAISE_APPLICATION_ERROR(
            -20001,
            'Operación rechazada: el saldo de la cuenta ' || :NEW.NUMERO_CUENTA ||
            ' quedaría en ' || TO_CHAR(:NEW.SALDO, 'FM999,999,999,990.00') ||
            ' (sobregiro no permitido).'
        );
    END IF;
END;
/

--==============================================================================
-- TRIGGER 2: AUDITORÍA DE CAMBIOS DE SALDO (COMPOUND TRIGGER)
--==============================================================================
/*
  Tipo          : COMPOUND TRIGGER
  Ventajas      :
    - Combina lógica de statement-level (a nivel de sentencia) y row-level (a nivel de fila) en un solo objeto
    - Evita el problema de "mutating table"es un error que ocurre 
        principalmente cuando un trigger de fila (FOR EACH ROW) intenta consultar o modificar la misma tabla 
        que está siendo modificada por ese trigger si en el futuro se necesita
    - Permite variables de estado compartidas entre las secciones


  Secciones usadas:
    BEFORE STATEMENT  → inicializa variables
    BEFORE EACH ROW   → captura valores OLD/NEW y prepara el registro
    AFTER STATEMENT   → inserta el registro de auditoría (más eficiente)

  Qué audita    : Cualquier UPDATE que modifique SALDO
  Usuario       : Intenta resolver el ID_USUARIO a partir de USER (sesión actual)
*/

CREATE OR REPLACE TRIGGER BANCO_CORE.TRG_AUDITORIA_CUENTAS_COMPOUND
FOR UPDATE OF SALDO ON BANCO_CORE.CUENTAS
COMPOUND TRIGGER

    -- Variables de estado del compound trigger (viven durante toda la sentencia)
    TYPE t_audit_rec IS RECORD (
        id_cuenta     BANCO_CORE.CUENTAS.ID_CUENTA%TYPE,
        numero_cuenta BANCO_CORE.CUENTAS.NUMERO_CUENTA%TYPE,
        saldo_ant     BANCO_CORE.CUENTAS.SALDO%TYPE,
        saldo_nuevo   BANCO_CORE.CUENTAS.SALDO%TYPE
    );
    TYPE t_audit_tab IS TABLE OF t_audit_rec INDEX BY PLS_INTEGER;

    v_auditoria  t_audit_tab;
    v_idx        PLS_INTEGER := 0;
    v_id_usuario BANCO_CORE.USUARIOS_SISTEMA.ID_USUARIO%TYPE;

    --==============================================================
    -- BEFORE STATEMENT
    -- Se ejecuta UNA sola vez al inicio de la sentencia UPDATE
    --==============================================================
    BEFORE STATEMENT IS
    BEGIN
        v_idx := 0;
        v_auditoria.DELETE;

        -- Resolver el usuario de la sesión una sola vez
        BEGIN
            SELECT ID_USUARIO
              INTO v_id_usuario
              FROM BANCO_CORE.USUARIOS_SISTEMA
             WHERE UPPER(NOMBRE_USUARIO) = UPPER(USER);
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_id_usuario := NULL;
            WHEN TOO_MANY_ROWS THEN
                v_id_usuario := NULL;
        END;
    END BEFORE STATEMENT;

    --==============================================================
    -- BEFORE EACH ROW
    -- Se ejecuta por cada fila afectada (antes de aplicar el cambio)
    -- Aquí capturamos los valores OLD y NEW
    --==============================================================
    BEFORE EACH ROW IS
    BEGIN
        v_idx := v_idx + 1;
        v_auditoria(v_idx).id_cuenta     := :NEW.ID_CUENTA;
        v_auditoria(v_idx).numero_cuenta := :NEW.NUMERO_CUENTA;
        v_auditoria(v_idx).saldo_ant     := :OLD.SALDO;
        v_auditoria(v_idx).saldo_nuevo   := :NEW.SALDO;
    END BEFORE EACH ROW;

    --==============================================================
    -- AFTER STATEMENT
    -- Se ejecuta UNA sola vez al final de la sentencia
    -- Aquí se realiza el INSERT masivo de auditoría (más eficiente)
    --==============================================================
    AFTER STATEMENT IS
    BEGIN
        IF v_auditoria.COUNT > 0 THEN
            FORALL i IN 1 .. v_auditoria.COUNT
                INSERT INTO BANCO_CORE.AUDITORIA (
                    ID_USUARIO,
                    ACCION,
                    ENTIDAD,
                    ID_ENTIDAD,
                    DETALLE,
                    FECHA_HORA
                ) VALUES (
                    v_id_usuario,
                    'UPDATE_SALDO',
                    'CUENTAS',
                    v_auditoria(i).id_cuenta,
                    'Usuario BD: ' || USER ||
                    ' | Cuenta: ' || v_auditoria(i).numero_cuenta ||
                    ' | Saldo anterior: ' || TO_CHAR(v_auditoria(i).saldo_ant, 'FM999,999,999,990.00') ||
                    ' | Saldo nuevo: '   || TO_CHAR(v_auditoria(i).saldo_nuevo, 'FM999,999,999,990.00'),
                    SYSTIMESTAMP
                );
        END IF;
    END AFTER STATEMENT;

END TRG_AUDITORIA_CUENTAS_COMPOUND;
/

--==============================================================================
-- VERIFICACIÓN INICIAL DE TRIGGERS CREADOS
--==============================================================================
SELECT TRIGGER_NAME,
       TRIGGER_TYPE,
       TRIGGERING_EVENT,
       STATUS,
       TABLE_NAME
FROM   DBA_TRIGGERS
WHERE  OWNER = 'BANCO_CORE'
ORDER  BY TRIGGER_NAME;


--==================================================================
-- PASO 3: Probar los triggers
--==================================================================
select * from BANCO_CORE.CUENTAS;
/*
1. Activa DBMS_OUTPUT
Si estás usando Oracle SQL Developer, ve a:
Ver → DBMS Output

o en inglés:
View → DBMS Output
Luego:
Aparecerá el panel DBMS Output abajo.
Presiona el botón + verde.
Selecciona tu conexión BANCO_CORE.
*/
-- 4.1 Debe FALLAR (sobregiro) → ORA-20001
--- Prueba 4.1: Intento de sobregiro (debe fallar) ---
BEGIN
    UPDATE BANCO_CORE.CUENTAS
       SET SALDO = -500
     WHERE NUMERO_CUENTA = '001-0002';

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error esperado: ' || SQLERRM);
        ROLLBACK;
END;
/

-- Verificar que el saldo NO cambió
SELECT NUMERO_CUENTA, SALDO
FROM   BANCO_CORE.CUENTAS
WHERE  NUMERO_CUENTA = '001-0002';


-- 4.2 Debe FUNCIONAR y generar auditoría
--- Prueba 4.2: Actualización válida (debe auditar) ---
UPDATE BANCO_CORE.CUENTAS
   SET SALDO = 1701
 WHERE NUMERO_CUENTA = '001-0002';
COMMIT;

-- Ver el registro de auditoría generado
SELECT ID_AUDITORIA,
       ID_USUARIO,
       ACCION,
       ENTIDAD,
       ID_ENTIDAD,
       DETALLE,
       FECHA_HORA
FROM   BANCO_CORE.AUDITORIA
ORDER  BY FECHA_HORA DESC
FETCH FIRST 5 ROWS ONLY;

--==================================================================
-- PASO 4: Ver triggers existentes
--==================================================================

SELECT TRIGGER_NAME,
       TABLE_NAME,
       TRIGGERING_EVENT,
       TRIGGER_TYPE,
       STATUS
FROM   DBA_TRIGGERS
WHERE  OWNER = 'BANCO_CORE'
ORDER  BY TRIGGER_NAME;



--==================================================================
-- PASO 5: Ver el código completo de un trigger específico
--==================================================================

--- Código de TRG_PREVENIR_SOBREGIRO ---
SELECT TEXT
FROM   DBA_SOURCE
WHERE  OWNER = 'BANCO_CORE'
  AND  NAME  = 'TRG_PREVENIR_SOBREGIRO'
ORDER  BY LINE;

 --- Código de TRG_AUDITORIA_CUENTAS_COMPOUND ---
SELECT TEXT
FROM   DBA_SOURCE
WHERE  OWNER = 'BANCO_CORE'
  AND  NAME  = 'TRG_AUDITORIA_CUENTAS_COMPOUND'
ORDER  BY LINE;

--==================================================================
-- PASO 6: Preparar usuario para que ID_USUARIO se resuelva correctamente
--==================================================================

SELECT ID_USUARIO, ID_ROL, NOMBRE_USUARIO, NOMBRE_COMPLETO, CORREO, ESTADO
FROM   BANCO_CORE.USUARIOS_SISTEMA
ORDER  BY ID_USUARIO;

SELECT * FROM  BANCO_CATALOGO.ROLES_SISTEMA;
/*
-- =====================================================================
-- BLOQUE OPCIONAL: Truncar tablas y reiniciar identity
-- (Úsalo SOLO si necesitas limpiar completamente los datos de prueba)
-- =====================================================================

UPDATE BANCO_CORE.AUDITORIA SET ID_USUARIO = NULL WHERE ID_USUARIO IS NOT NULL;
COMMIT;

-- Deshabilitar constraints que referencian USUARIOS_SISTEMA
-- (los nombres SYS_C00xxxx pueden variar; ajústalos según tu ambiente)
ALTER TABLE BANCO_CORE.TRANSFERENCIAS DISABLE CONSTRAINT SYS_C008546;
ALTER TABLE BANCO_CORE.AUDITORIA      DISABLE CONSTRAINT SYS_C008563;

TRUNCATE TABLE BANCO_CORE.USUARIOS_SISTEMA;

ALTER TABLE BANCO_CORE.USUARIOS_SISTEMA
MODIFY ID_USUARIO GENERATED ALWAYS AS IDENTITY (START WITH 1);

TRUNCATE TABLE BANCO_CORE.AUDITORIA;

ALTER TABLE BANCO_CORE.AUDITORIA
MODIFY ID_USUARIO GENERATED ALWAYS AS IDENTITY (START WITH 1);

-- Volver a habilitar constraints
ALTER TABLE BANCO_CORE.TRANSFERENCIAS ENABLE CONSTRAINT SYS_C008546;
ALTER TABLE BANCO_CORE.AUDITORIA      ENABLE CONSTRAINT SYS_C008563;
*/

-- Insertar (o asegurar) un usuario que coincida con el USER de la sesión
-- Cambia 'DBA_5308' por el nombre de usuario con el que te conectas
INSERT INTO BANCO_CORE.USUARIOS_SISTEMA (ID_ROL, NOMBRE_USUARIO, NOMBRE_COMPLETO, CORREO)
SELECT 1, 'DBA_5308', 'Administrador DBA', 'dba@banco.com'
FROM   DUAL
WHERE  NOT EXISTS (
    SELECT 1 FROM BANCO_CORE.USUARIOS_SISTEMA
    WHERE  UPPER(NOMBRE_USUARIO) = 'DBA_5308'
);
COMMIT;

--==================================================================
-- PASO 7: Deshabilitar / habilitar / eliminar triggers
--==================================================================
-- 7.1 Deshabilitar el trigger de prevención

 --- Deshabilitando TRG_PREVENIR_SOBREGIRO ---
ALTER TRIGGER BANCO_CORE.TRG_PREVENIR_SOBREGIRO DISABLE;

-- 7.2 Verificar estado
SELECT TRIGGER_NAME, STATUS
FROM   DBA_TRIGGERS
WHERE  OWNER = 'BANCO_CORE'
ORDER  BY TRIGGER_NAME;

-- 7.3 Habilitar de nuevo

 --- Habilitando TRG_PREVENIR_SOBREGIRO ---
ALTER TRIGGER BANCO_CORE.TRG_PREVENIR_SOBREGIRO ENABLE;

-- Verificar estado final
SELECT TRIGGER_NAME, STATUS
FROM   DBA_TRIGGERS
WHERE  OWNER = 'BANCO_CORE'
ORDER  BY TRIGGER_NAME;

-- 7.4 Segunda prueba (después de habilitar)

 --- Segunda prueba de actualización válida ---
UPDATE BANCO_CORE.CUENTAS
   SET SALDO = 1900
 WHERE NUMERO_CUENTA = '001-0002';
COMMIT;

-- Ver auditoría generada
SELECT ID_AUDITORIA,
       ID_USUARIO,
       ACCION,
       ENTIDAD,
       ID_ENTIDAD,
       DETALLE,
       FECHA_HORA
FROM   BANCO_CORE.AUDITORIA
ORDER  BY FECHA_HORA DESC
FETCH FIRST 5 ROWS ONLY;



--==================================================================
-- PASO 8: LIMPIEZA SEGURA DE TRIGGERS (para poder re-ejecutar el script)
--==================================================================
/*
  Descomenta este bloque SOLO cuando quieras eliminar los triggers
  y volver a ejecutar el script desde cero.
*/

/*
BEGIN
    EXECUTE IMMEDIATE 'ALTER TRIGGER BANCO_CORE.TRG_PREVENIR_SOBREGIRO DISABLE';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

BEGIN
    EXECUTE IMMEDIATE 'ALTER TRIGGER BANCO_CORE.TRG_AUDITORIA_CUENTAS_COMPOUND DISABLE';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

-- Eliminar de forma segura
BEGIN
    EXECUTE IMMEDIATE 'DROP TRIGGER BANCO_CORE.TRG_PREVENIR_SOBREGIRO';
    DBMS_OUTPUT.PUT_LINE('TRG_PREVENIR_SOBREGIRO eliminado.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('TRG_PREVENIR_SOBREGIRO no existía o ya fue eliminado.');
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP TRIGGER BANCO_CORE.TRG_AUDITORIA_CUENTAS_COMPOUND';
    DBMS_OUTPUT.PUT_LINE('TRG_AUDITORIA_CUENTAS_COMPOUND eliminado.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('TRG_AUDITORIA_CUENTAS_COMPOUND no existía o ya fue eliminado.');
END;
/

-- Verificación final
SELECT TRIGGER_NAME, STATUS
FROM   DBA_TRIGGERS
WHERE  OWNER = 'BANCO_CORE'
ORDER  BY TRIGGER_NAME;

*/



