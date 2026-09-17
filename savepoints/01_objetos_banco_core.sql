/*==============================================================================
  PROYECTO: MODULO DE TRANSFERENCIAS INTERCUENTAS - ORACLE XE 21c
  REQUISITO 5: USO ESTRATEGICO DE SAVEPOINTS PARA RECUPERACION PARCIAL
  ESQUEMAS: BANCO_CORE (transaccional) / BANCO_CATALOGO (catalogos)
==============================================================================*/

/*  ARCHIVO 01 - EJECUTAR CONECTADO COMO BANCO_CORE
    Crea la bitacora autonoma, las funciones de catalogo, los tipos del lote
    y los dos procedimientos del modulo.                                     */

SET SERVEROUTPUT ON SIZE UNLIMITED;

/*==============================================================================
  SECCION 1: BITACORA AUTONOMA

  PUNTO CLAVE DEL MODULO:
  Un ROLLBACK TO SAVEPOINT tambien borra los INSERT de auditoria hechos
  despues del savepoint. Si la bitacora se escribe en la misma transaccion,
  el rastro del fallo desaparece justo cuando mas se necesita.

  Solucion: PRAGMA AUTONOMOUS_TRANSACTION. El registro se escribe en una
  transaccion independiente, hace su propio COMMIT y SOBREVIVE al rollback
  parcial de la transaccion principal.
==============================================================================*/

CREATE OR REPLACE PROCEDURE BANCO_CORE.PRC_LOG_AUDITORIA (
    p_accion     IN VARCHAR2,
    p_entidad    IN VARCHAR2,
    p_id_entidad IN NUMBER,
    p_detalle    IN VARCHAR2
) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
    v_id_usuario BANCO_CORE.USUARIOS_SISTEMA.ID_USUARIO%TYPE;
BEGIN
    BEGIN
        SELECT ID_USUARIO
          INTO v_id_usuario
          FROM BANCO_CORE.USUARIOS_SISTEMA
         WHERE UPPER(NOMBRE_USUARIO) = UPPER(USER);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN v_id_usuario := NULL;
        WHEN TOO_MANY_ROWS THEN v_id_usuario := NULL;
    END;

    INSERT INTO BANCO_CORE.AUDITORIA
        (ID_USUARIO, ACCION, ENTIDAD, ID_ENTIDAD, DETALLE, FECHA_HORA)
    VALUES
        (v_id_usuario, p_accion, p_entidad, p_id_entidad,
         SUBSTR(p_detalle, 1, 1000), SYSTIMESTAMP);

    COMMIT;   -- COMMIT de la transaccion autonoma, NO de la principal
END;
/


/*==============================================================================
  SECCION 2: FUNCIONES DE APOYO PARA CATALOGOS
==============================================================================*/

CREATE OR REPLACE FUNCTION BANCO_CORE.FN_ID_ESTADO_TRANSF (
    p_nombre IN VARCHAR2
) RETURN NUMBER IS
    v_id NUMBER;
BEGIN
    SELECT ID_ESTADO_TRANSFERENCIA
      INTO v_id
      FROM BANCO_CATALOGO.ESTADOS_TRANSFERENCIA
     WHERE UPPER(NOMBRE_ESTADO) = UPPER(p_nombre);
    RETURN v_id;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20050,
            'No existe el estado de transferencia: ' || p_nombre);
END;
/

CREATE OR REPLACE FUNCTION BANCO_CORE.FN_ID_TIPO_MOV (
    p_nombre IN VARCHAR2
) RETURN NUMBER IS
    v_id NUMBER;
BEGIN
    SELECT ID_TIPO_MOVIMIENTO
      INTO v_id
      FROM BANCO_CATALOGO.TIPOS_MOVIMIENTO
     WHERE UPPER(NOMBRE_TIPO) = UPPER(p_nombre);
    RETURN v_id;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20051,
            'No existe el tipo de movimiento: ' || p_nombre);
END;
/


/*==============================================================================
  SECCION 3: TIPOS PARA EL PROCESAMIENTO POR LOTE (ESCENARIO B)
==============================================================================*/

CREATE OR REPLACE TYPE BANCO_CORE.T_TRANSFERENCIA_ITEM AS OBJECT (
    ID_CUENTA_ORIGEN  NUMBER,
    ID_CUENTA_DESTINO NUMBER,
    MONTO             NUMBER
);
/

CREATE OR REPLACE TYPE BANCO_CORE.T_LOTE_TRANSFERENCIAS
    AS TABLE OF BANCO_CORE.T_TRANSFERENCIA_ITEM;
/


/*==============================================================================
  SECCION 4: PROCEDIMIENTO PRINCIPAL CON SAVEPOINTS ESCALONADOS

  MAPA DE SAVEPOINTS
  ------------------
    SP_INICIO        -> antes de tocar nada. Punto de reversion total logica.
    SP_DEBITO        -> despues de descontar de la cuenta origen.
    SP_CREDITO       -> despues de abonar a la cuenta destino.
    SP_TRANSFERENCIA -> despues de grabar el encabezado en TRANSFERENCIAS.

  POLITICA DE RECUPERACION
  ------------------------
    Fallo en debito o credito  -> ROLLBACK TO SP_INICIO (nada queda aplicado).
    Fallo en el historico      -> ROLLBACK TO SP_TRANSFERENCIA: los saldos y el
                                  encabezado SOBREVIVEN, la transferencia se
                                  marca PARCIAL y queda para reproceso.

  NOTA DE DISEÑO: el procedimiento NO relanza la excepcion; informa el
  desenlace por P_RESULTADO y deja el rastro en AUDITORIA. Esto es lo que
  permite que el lote de la seccion 5 siga procesando las demas operaciones.
==============================================================================*/

CREATE OR REPLACE PROCEDURE BANCO_CORE.PRC_TRANSFERENCIA_SP (
    p_cuenta_origen  IN  NUMBER,
    p_cuenta_destino IN  NUMBER,
    p_monto          IN  NUMBER,
    p_id_usuario     IN  NUMBER,
    p_resultado      OUT VARCHAR2,
    p_commit         IN  VARCHAR2 DEFAULT 'S',   -- 'N' cuando se llama desde un lote
    p_simular_fallo  IN  VARCHAR2 DEFAULT 'N'    -- 'S' fuerza el fallo en la fase 4
) IS
    v_saldo_origen  BANCO_CORE.CUENTAS.SALDO%TYPE;
    v_saldo_destino BANCO_CORE.CUENTAS.SALDO%TYPE;
    v_id_transf     BANCO_CORE.TRANSFERENCIAS.ID_TRANSFERENCIA%TYPE;
    v_tipo_debito   NUMBER;
    v_tipo_credito  NUMBER;

    -- El sobregiro puede bloquearse por DOS caminos distintos:
    --   ORA-20001 -> trigger TRG_PREVENIR_SOBREGIRO
    --   ORA-02290 -> CHECK CK_CUENTAS_SALDO definido en proyecto_v1.sql
    -- Se capturan ambos porque el trigger puede estar deshabilitado o borrado
    -- (tu script de triggers termina con un DROP TRIGGER) y el CHECK sigue vivo.
    e_sobregiro EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_sobregiro, -20001);

    e_check_saldo EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_check_saldo, -2290);
BEGIN
    /*--------------------------------------------------------------
      SAVEPOINT 1: punto cero de la operacion.
      Si esta rutina se llama dentro de una transaccion mas grande,
      ROLLBACK TO SP_INICIO deshace SOLO esta transferencia y respeta
      todo el trabajo previo del llamador. Un ROLLBACK a secas no.
    ---------------------------------------------------------------*/
    SAVEPOINT SP_INICIO;

    -- Validaciones de entrada
    IF p_monto IS NULL OR p_monto <= 0 THEN
        p_resultado := 'RECHAZADO: el monto debe ser mayor a cero';
        RETURN;
    END IF;

    IF p_cuenta_origen = p_cuenta_destino THEN
        p_resultado := 'RECHAZADO: cuenta origen y destino son la misma';
        RETURN;
    END IF;

    v_tipo_debito  := BANCO_CORE.FN_ID_TIPO_MOV('DEBITO');
    v_tipo_credito := BANCO_CORE.FN_ID_TIPO_MOV('CREDITO');

    /*--------------------------------------------------------------
      FASE 1: DEBITO EN LA CUENTA ORIGEN
      Aqui puede dispararse TRG_PREVENIR_SOBREGIRO (ORA-20001).
      Ajusta ESTADO = 'A' si en tu carga de datos usas otra letra.
    ---------------------------------------------------------------*/
    UPDATE BANCO_CORE.CUENTAS
       SET SALDO            = SALDO - p_monto,
           FECHA_ULTIMA_MOD = SYSTIMESTAMP
     WHERE ID_CUENTA = p_cuenta_origen
       AND ESTADO    = 'A'
    RETURNING SALDO INTO v_saldo_origen;

    IF SQL%ROWCOUNT = 0 THEN
        ROLLBACK TO SP_INICIO;
        BANCO_CORE.PRC_LOG_AUDITORIA(
            'ROLLBACK_TO_SP_INICIO', 'CUENTAS', p_cuenta_origen,
            'Cuenta origen inexistente o inactiva. Transferencia abortada.');
        p_resultado := 'RECHAZADO: cuenta origen inexistente o inactiva';
        IF p_commit = 'S' THEN COMMIT; END IF;
        RETURN;
    END IF;

    SAVEPOINT SP_DEBITO;   -- SAVEPOINT 2

    /*--------------------------------------------------------------
      FASE 2: CREDITO EN LA CUENTA DESTINO
      Si la cuenta destino no existe, el debito ya aplicado NO puede
      quedarse: se revierte hasta SP_INICIO. Dinero que desaparece es
      exactamente lo que la atomicidad debe impedir.
    ---------------------------------------------------------------*/
    UPDATE BANCO_CORE.CUENTAS
       SET SALDO            = SALDO + p_monto,
           FECHA_ULTIMA_MOD = SYSTIMESTAMP
     WHERE ID_CUENTA = p_cuenta_destino
       AND ESTADO    = 'A'
    RETURNING SALDO INTO v_saldo_destino;

    IF SQL%ROWCOUNT = 0 THEN
        ROLLBACK TO SP_INICIO;
        BANCO_CORE.PRC_LOG_AUDITORIA(
            'ROLLBACK_TO_SP_INICIO', 'CUENTAS', p_cuenta_destino,
            'Cuenta destino inexistente o inactiva. Se revirtio el debito de '
            || p_monto || ' aplicado a la cuenta ' || p_cuenta_origen);
        p_resultado := 'RECHAZADO: cuenta destino inexistente o inactiva';
        IF p_commit = 'S' THEN COMMIT; END IF;
        RETURN;
    END IF;

    SAVEPOINT SP_CREDITO;  -- SAVEPOINT 3

    /*--------------------------------------------------------------
      FASE 3: ENCABEZADO DE LA TRANSFERENCIA
    ---------------------------------------------------------------*/
    INSERT INTO BANCO_CORE.TRANSFERENCIAS
        (ID_CUENTA_ORIGEN, ID_CUENTA_DESTINO, MONTO,
         ID_ESTADO_TRANSFERENCIA, FECHA_TRANSACCION, ID_USUARIO)
    VALUES
        (p_cuenta_origen, p_cuenta_destino, p_monto,
         BANCO_CORE.FN_ID_ESTADO_TRANSF('COMPLETADA'), SYSTIMESTAMP, p_id_usuario)
    RETURNING ID_TRANSFERENCIA INTO v_id_transf;

    SAVEPOINT SP_TRANSFERENCIA;  -- SAVEPOINT 4

    /*--------------------------------------------------------------
      FASE 4: REGISTRO HISTORICO (NO CRITICO)
      Es la unica fase de la que se puede prescindir sin corromper los
      saldos. Por eso su bloque de excepcion NO revierte la operacion
      completa: revierte hasta SP_TRANSFERENCIA, deja el dinero movido y
      degrada el estado a PARCIAL. Eso es recuperacion parcial.
    ---------------------------------------------------------------*/
    BEGIN
        -- Inyeccion de fallo controlado para la demostracion:
        -- un ID_TIPO_MOVIMIENTO inexistente viola la FK.
        IF p_simular_fallo = 'S' THEN
            v_tipo_debito := -99;
        END IF;

        INSERT INTO BANCO_CORE.MOVIMIENTOS_CUENTA
            (ID_CUENTA, ID_TIPO_MOVIMIENTO, DEBITO, CREDITO,
             SALDO_RESULTANTE, FECHA, ID_TRANSFERENCIA)
        VALUES
            (p_cuenta_origen, v_tipo_debito, p_monto, 0,
             v_saldo_origen, SYSTIMESTAMP, v_id_transf);

        INSERT INTO BANCO_CORE.MOVIMIENTOS_CUENTA
            (ID_CUENTA, ID_TIPO_MOVIMIENTO, DEBITO, CREDITO,
             SALDO_RESULTANTE, FECHA, ID_TRANSFERENCIA)
        VALUES
            (p_cuenta_destino, v_tipo_credito, 0, p_monto,
             v_saldo_destino, SYSTIMESTAMP, v_id_transf);

        p_resultado := 'COMPLETADO';

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO SP_TRANSFERENCIA;   -- <<< RECUPERACION PARCIAL

            UPDATE BANCO_CORE.TRANSFERENCIAS
               SET ID_ESTADO_TRANSFERENCIA = BANCO_CORE.FN_ID_ESTADO_TRANSF('PARCIAL')
             WHERE ID_TRANSFERENCIA = v_id_transf;

            BANCO_CORE.PRC_LOG_AUDITORIA(
                'ROLLBACK_TO_SP_TRANSFERENCIA', 'TRANSFERENCIAS', v_id_transf,
                'Fallo el registro en MOVIMIENTOS_CUENTA. Saldos y encabezado '
                || 'conservados, historico descartado. Error: '
                || SUBSTR(SQLERRM, 1, 300));

            p_resultado := 'PARCIAL';
    END;

    BANCO_CORE.PRC_LOG_AUDITORIA(
        'TRANSFERENCIA_' || p_resultado, 'TRANSFERENCIAS', v_id_transf,
        'Monto ' || p_monto || ' de cuenta ' || p_cuenta_origen
        || ' a cuenta ' || p_cuenta_destino
        || '. Saldo origen: '  || v_saldo_origen
        || '. Saldo destino: ' || v_saldo_destino);

    IF p_commit = 'S' THEN
        COMMIT;
    END IF;

EXCEPTION
    /*--------------------------------------------------------------
      Sobregiro detectado por el trigger BEFORE UPDATE.
      Importante: RAISE_APPLICATION_ERROR dentro de un trigger solo
      revierte la SENTENCIA que fallo, no la transaccion completa. El
      ROLLBACK TO SP_INICIO es lo que garantiza que no quede ningun
      tramo aplicado a medias.
    ---------------------------------------------------------------*/
    WHEN e_sobregiro THEN
        ROLLBACK TO SP_INICIO;
        BANCO_CORE.PRC_LOG_AUDITORIA(
            'ROLLBACK_TO_SP_INICIO', 'CUENTAS', p_cuenta_origen,
            'Sobregiro rechazado por trigger. Monto solicitado: ' || p_monto
            || '. ' || SUBSTR(SQLERRM, 1, 250));
        p_resultado := 'RECHAZADO: fondos insuficientes (sobregiro)';
        IF p_commit = 'S' THEN COMMIT; END IF;

    WHEN e_check_saldo THEN
        ROLLBACK TO SP_INICIO;
        BANCO_CORE.PRC_LOG_AUDITORIA(
            'ROLLBACK_TO_SP_INICIO', 'CUENTAS', p_cuenta_origen,
            'Sobregiro rechazado por CHECK CK_CUENTAS_SALDO. Monto solicitado: '
            || p_monto || '. ' || SUBSTR(SQLERRM, 1, 250));
        p_resultado := 'RECHAZADO: fondos insuficientes (restriccion de saldo)';
        IF p_commit = 'S' THEN COMMIT; END IF;

    WHEN OTHERS THEN
        ROLLBACK TO SP_INICIO;
        BANCO_CORE.PRC_LOG_AUDITORIA(
            'ROLLBACK_TO_SP_INICIO', 'TRANSFERENCIAS', NULL,
            'Error no controlado: ' || SUBSTR(SQLERRM, 1, 400));
        p_resultado := 'ERROR: ' || SUBSTR(SQLERRM, 1, 200);
        IF p_commit = 'S' THEN COMMIT; END IF;
END;
/


/*==============================================================================
  SECCION 5: PROCESAMIENTO POR LOTE - UN SAVEPOINT POR OPERACION

  Sin savepoints, una sola transferencia invalida obligaria a botar el lote
  entero. Con SAVEPOINT SP_ITEM antes de cada operacion, la fallida se
  descarta y el resto se confirma en el COMMIT final.

  El nombre SP_ITEM se reutiliza en cada vuelta: Oracle mueve el savepoint
  al punto nuevo y descarta el anterior. Es valido y es lo que se busca.
==============================================================================*/

CREATE OR REPLACE PROCEDURE BANCO_CORE.PRC_LOTE_TRANSFERENCIAS (
    p_lote       IN BANCO_CORE.T_LOTE_TRANSFERENCIAS,
    p_id_usuario IN NUMBER
) IS
    v_resultado VARCHAR2(300);
    v_ok        NUMBER := 0;
    v_parcial   NUMBER := 0;
    v_fallidas  NUMBER := 0;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== PROCESAMIENTO DE LOTE: '
        || p_lote.COUNT || ' operaciones ===');

    FOR i IN 1 .. p_lote.COUNT LOOP

        SAVEPOINT SP_ITEM;   -- punto de reversion de ESTA operacion

        BEGIN
            BANCO_CORE.PRC_TRANSFERENCIA_SP(
                p_cuenta_origen  => p_lote(i).ID_CUENTA_ORIGEN,
                p_cuenta_destino => p_lote(i).ID_CUENTA_DESTINO,
                p_monto          => p_lote(i).MONTO,
                p_id_usuario     => p_id_usuario,
                p_resultado      => v_resultado,
                p_commit         => 'N',   -- el COMMIT lo controla el lote
                p_simular_fallo  => 'N'
            );

            IF v_resultado = 'COMPLETADO' THEN
                v_ok := v_ok + 1;
            ELSIF v_resultado = 'PARCIAL' THEN
                v_parcial := v_parcial + 1;
            ELSE
                ROLLBACK TO SP_ITEM;   -- descarta solo esta operacion
                v_fallidas := v_fallidas + 1;
            END IF;

        EXCEPTION
            WHEN OTHERS THEN
                ROLLBACK TO SP_ITEM;
                v_fallidas := v_fallidas + 1;
                v_resultado := 'ERROR: ' || SUBSTR(SQLERRM, 1, 200);
                BANCO_CORE.PRC_LOG_AUDITORIA(
                    'ROLLBACK_TO_SP_ITEM', 'TRANSFERENCIAS', NULL,
                    'Operacion ' || i || ' del lote descartada. ' || v_resultado);
        END;

        DBMS_OUTPUT.PUT_LINE('  Op ' || i || ' | cuenta '
            || p_lote(i).ID_CUENTA_ORIGEN || ' -> ' || p_lote(i).ID_CUENTA_DESTINO
            || ' | monto ' || p_lote(i).MONTO || ' | ' || v_resultado);

    END LOOP;

    COMMIT;   -- confirma unicamente las operaciones que sobrevivieron

    DBMS_OUTPUT.PUT_LINE('=== RESUMEN: ' || v_ok || ' completadas, '
        || v_parcial || ' parciales, ' || v_fallidas || ' descartadas ===');
END;
/
