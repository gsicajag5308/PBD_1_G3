/*==============================================================================
  PROYECTO: MODULO DE TRANSFERENCIAS INTERCUENTAS - ORACLE XE 21c
  REQUISITO 5: USO ESTRATEGICO DE SAVEPOINTS PARA RECUPERACION PARCIAL
  ESQUEMAS: BANCO_CORE (transaccional) / BANCO_CATALOGO (catalogos)
==============================================================================*/

/*  ARCHIVO 99 - OPCIONAL, COMO BANCO_CORE
    Elimina unicamente los objetos creados por este modulo.
    No toca tablas ni datos del proyecto.                                    */

DROP PROCEDURE BANCO_CORE.PRC_LOTE_TRANSFERENCIAS;
DROP PROCEDURE BANCO_CORE.PRC_TRANSFERENCIA_SP;
DROP PROCEDURE BANCO_CORE.PRC_LOG_AUDITORIA;
DROP FUNCTION  BANCO_CORE.FN_ID_ESTADO_TRANSF;
DROP FUNCTION  BANCO_CORE.FN_ID_TIPO_MOV;
DROP TYPE      BANCO_CORE.T_LOTE_TRANSFERENCIAS;
DROP TYPE      BANCO_CORE.T_TRANSFERENCIA_ITEM;
