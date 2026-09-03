--==================================================================
-- Triggers para prevención de sobregiros y auditoría.
--==================================================================


--==============================================================================
-- PASO 1: Permitir crear usuarios sin restricciones de contraseña
--==============================================================================

ALTER SESSION SET "_ORACLE_SCRIPT" = true;

--==================================================================
--Paso 2 Trigger de prevención de sobregiros
-- Este trigger revisa que el saldo nunca quede negativo al hacer un UPDATE sobre CUENTAS
--==================================================================


CREATE OR REPLACE TRIGGER BANCO_CORE.TRG_PREVENIR_SOBREGIRO
BEFORE UPDATE OF SALDO ON BANCO_CORE.CUENTAS
FOR EACH ROW
BEGIN
    IF :NEW.SALDO < 0 THEN
        RAISE_APPLICATION_ERROR(
            -20001,
            'Operación rechazada: el saldo de la cuenta ' || :NEW.NUMERO_CUENTA ||
            ' quedaría en ' || :NEW.SALDO || ' (sobregiro no permitido).'
        );
    END IF;
END;
/

/*
    BEFORE UPDATE OF SALDO → solo se dispara si el UPDATE toca la columna SALDO (no cualquier UPDATE a la tabla).
    :NEW.SALDO → el valor que tendría el saldo después de aplicar el cambio (aún no se ha guardado).
    RAISE_APPLICATION_ERROR(-20001, ...) → cancela la transacción completa y devuelve un error personalizado al usuario. 
    El código debe estar entre -20000 y -20999 (rango reservado para errores de aplicación).
*/


--==================================================================
--Paso 3 Trigger de auditoría automática
-- Este trigger inserta un registro en tu tabla AUDITORIA cada vez que se modifica el saldo de una cuenta 
-- automatizando lo que antes tendrías que hacer manualmente desde la aplicación.
--==================================================================

CREATE OR REPLACE TRIGGER BANCO_CORE.TRG_AUDITORIA_CUENTAS
AFTER UPDATE OF SALDO ON BANCO_CORE.CUENTAS
FOR EACH ROW
BEGIN
    INSERT INTO BANCO_CORE.AUDITORIA (ID_USUARIO, ACCION, ENTIDAD, ID_ENTIDAD, DETALLE)
    VALUES (
        NULL,  -- si tuvieras el usuario de aplicación disponible, iría aquí
        'UPDATE_SALDO',
        'CUENTAS',
        :NEW.ID_CUENTA,
        'Saldo anterior: ' || :OLD.SALDO || ' | Saldo nuevo: ' || :NEW.SALDO
    );
END;
/


/*
TRG_PREVENIR_SOBREGIRO (BEFORE) — si rechaza, el AFTER nunca se ejecuta.
TRG_AUDITORIA_CUENTAS (AFTER) — solo si el BEFORE lo permitió.
*/


--==================================================================
--Paso 4 Probar los triggers
--==================================================================

-- Debe fallar (sobregiro)

UPDATE BANCO_CORE.CUENTAS SET SALDO = -500 WHERE NUMERO_CUENTA = '001-0002';
select * from  BANCO_CORE.CUENTAS  WHERE NUMERO_CUENTA = '001-0002';
-- Debe darte tu error personalizado ORA-20001.

-- Debe funcionar y auditar

UPDATE BANCO_CORE.CUENTAS SET SALDO = 1700 WHERE NUMERO_CUENTA = '001-0002';
COMMIT;

SELECT * FROM BANCO_CORE.AUDITORIA ORDER BY FECHA_HORA DESC;

--==================================================================
--Paso 5 Ver triggers existentes
--==================================================================

SELECT TRIGGER_NAME, TABLE_NAME, TRIGGERING_EVENT, TRIGGER_TYPE, STATUS
FROM DBA_TRIGGERS
WHERE OWNER = 'BANCO_CORE';

--==================================================================
--Paso 6 Para ver el código completo de un trigger específico:
--==================================================================

SELECT TEXT FROM DBA_SOURCE
WHERE OWNER = 'BANCO_CORE' AND NAME = 'TRG_PREVENIR_SOBREGIRO'
ORDER BY LINE;

--==================================================================
--Paso 7 Modificar un trigger
--==================================================================

-- Para que la coluna id_usuario debe  e existir en la tabla USUARIOS_SISTEMA
--------
SELECT * FROM BANCO_CORE.USUARIOS_SISTEMA;
/* 
-- truncar tabals y reiniciar identity
UPDATE BANCO_CORE.AUDITORIA SET ID_USUARIO = NULL WHERE ID_USUARIO IS NOT NULL;
COMMIT;
ALTER TABLE BANCO_CORE.TRANSFERENCIAS DISABLE CONSTRAINT SYS_C008546;
ALTER TABLE BANCO_CORE.AUDITORIA DISABLE CONSTRAINT SYS_C008563;

TRUNCATE TABLE BANCO_CORE.USUARIOS_SISTEMA;

ALTER TABLE BANCO_CORE.USUARIOS_SISTEMA
MODIFY ID_USUARIO GENERATED ALWAYS AS IDENTITY (START WITH 1);

TRUNCATE TABLE BANCO_CORE.AUDITORIA;
ALTER TABLE BANCO_CORE.AUDITORIA
MODIFY ID_USUARIO GENERATED ALWAYS AS IDENTITY (START WITH 1);

ALTER TABLE BANCO_CORE.TRANSFERENCIAS ENABLE CONSTRAINT SYS_C008546;
ALTER TABLE BANCO_CORE.AUDITORIA ENABLE CONSTRAINT SYS_C008563;

*/

INSERT INTO BANCO_CORE.USUARIOS_SISTEMA (ID_ROL, NOMBRE_USUARIO, NOMBRE_COMPLETO, CORREO)
VALUES (1, 'DBA_5308', 'Administrador DBA', 'dba@banco.com');
COMMIT;

CREATE OR REPLACE TRIGGER BANCO_CORE.TRG_AUDITORIA_CUENTAS
AFTER UPDATE OF SALDO ON BANCO_CORE.CUENTAS
FOR EACH ROW
DECLARE
    v_id_usuario BANCO_CORE.USUARIOS_SISTEMA.ID_USUARIO%TYPE;
BEGIN
    BEGIN
        SELECT ID_USUARIO INTO v_id_usuario
        FROM BANCO_CORE.USUARIOS_SISTEMA
        WHERE UPPER(NOMBRE_USUARIO) = UPPER(USER);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_id_usuario := NULL;
    END;

    INSERT INTO BANCO_CORE.AUDITORIA (ID_USUARIO, ACCION, ENTIDAD, ID_ENTIDAD, DETALLE)
    VALUES (
        v_id_usuario,
        'UPDATE_SALDO',
        'CUENTAS',
        :NEW.ID_CUENTA,
        'Usuario BD: ' || USER ||
        ' | Saldo anterior: ' || :OLD.SALDO ||
        ' | Saldo nuevo: ' || :NEW.SALDO
    );
END;
/

--==================================================================
--Paso 8 Deshabilitar / habilitar (sin eliminar)
--==================================================================

-- Deshabilitar
ALTER TRIGGER BANCO_CORE.TRG_PREVENIR_SOBREGIRO DISABLE;

-- Habilitar de nuevo
ALTER TRIGGER BANCO_CORE.TRG_PREVENIR_SOBREGIRO ENABLE;
-- Verificar estado:
SELECT TRIGGER_NAME, STATUS FROM DBA_TRIGGERS WHERE OWNER = 'BANCO_CORE';
--Eliminar un trigger
DROP TRIGGER BANCO_CORE.TRG_PREVENIR_SOBREGIRO;


-- segunda prueba 
UPDATE BANCO_CORE.CUENTAS SET SALDO = 1900 WHERE NUMERO_CUENTA = '001-0002';
COMMIT;

SELECT * FROM BANCO_CORE.AUDITORIA  ORDER BY FECHA_HORA DESC;


