SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

UPDATE BANCO_CORE.CUENTAS SET SALDO = SALDO - 50 WHERE ID_CUENTA = 1;

-- NO hagas COMMIT todavía. Deja esta sesión "congelada" aquí.

EXEC BANCO_CORE.prc_transferencia_timestamp(1, 2, 100, 1, 'Prueba concurrencia B');

--
COMMIT;
