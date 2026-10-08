# Pruebas de caída de sesión y pérdida de conexión

Estas pruebas complementan el procedimiento ACID instalado. Se ejecutan por pasos; no se ejecutan los archivos completos de una vez. No requieren crear tablas, usuarios ni modificar el procedimiento.

## Archivos y conexiones

| Archivo | Dónde se utiliza | Función |
| --- | --- | --- |
| 19_PRUEBA_CAIDA_SESION.sql | BANCO_CORE_PROYECTO, SQL Developer | Dejar un débito pendiente y verificar los saldos tras la caída. |
| 20_CAIDA_SESION_SYS.sql | SYS_PROYECTO_BANCO, SQL Developer | Terminar la sesión de prueba y comprobar la recuperación. |
| 21_PRUEBA_PERDIDA_CONEXION.sql | BANCO_CORE_PROYECTO, SQL Developer | Dejar un débito pendiente, cortar la red y verificar los saldos finales. |
| 22_PERDIDA_CONEXION_SYS.sql | SYS_PROYECTO_BANCO; una consulta en la terminal local durante el corte | Revisar si la transacción sigue pendiente y cerrar la sesión antigua si es necesario. |

Los archivos 19 y 20 ya se guardaron anteriormente. Los archivos 21 y 22 documentan la prueba de pérdida de conexión que acabamos de realizar.

## Forma de trabajo

Seguir los comentarios de cada archivo. F5 se utiliza con el bloque seleccionado; Ctrl + Enter, con la consulta indicada. El débito se ejecuta una sola vez y no se confirma. Anotar los saldos iniciales, el SID y el SERIAL# actuales antes de provocar el fallo.

Todo se hace en SQL Developer salvo desactivar y restaurar el cable virtual en VirtualBox y consultar la sesión desde la terminal de la VM mientras la red está cortada. Para esa consulta local se abre SQL*Plus con `sqlplus / as sysdba`. Tras restaurar la red, se vuelve a SQL Developer.

## Resultados observados el 7 de octubre de 2026

**Caída de sesión:** partimos de Q15000 y Q4000. Se descontaron Q100 sin COMMIT. Al terminar la sesión desde SYS, Oracle revirtió ese cambio y los saldos volvieron a Q15000 y Q4000, sin ejecutar un ROLLBACK manual.

**Pérdida de conexión:** partimos de Q15000 y Q4000. El débito de Q100 se ejecutó dos veces por accidente, dejando Q14800 y Q4000 dentro de la sesión. Al cortar la red, la transacción permaneció pendiente. SQL Developer reconectó y mostró los datos confirmados, pero la sesión antigua aún tenía una transacción asociada. Se terminó manualmente esa sesión desde SYS. La consulta posterior no encontró la sesión y los saldos finales fueron Q15000 y Q4000.

Por tanto, esta segunda prueba demuestra pérdida de conexión con recuperación administrativa manual. Ver los saldos originales desde otra sesión no prueba, por sí solo, que la transacción antigua haya sido revertida.

## Evidencias

Guardar capturas de los saldos iniciales, el débito pendiente, la sesión identificada, el estado durante el corte, el aviso de reconexión, la sesión liberada y los saldos finales. Para la caída de sesión, conservar también el comando de terminación y la recuperación de saldos.

## Alcance

Se reprodujo el punto intermedio de una transferencia mediante un débito sin confirmar. No se interrumpió una llamada a REALIZAR_TRANSFERENCIA: ese procedimiento confirma al finalizar. Estas pruebas muestran recuperación de cambios pendientes; no demuestran por sí solas las cuatro propiedades ACID ni sustituyen una prueba específica de error dentro del procedimiento.

Estos archivos no vuelven a ejecutar las pruebas al guardarlos. Se pueden añadir al repositorio junto a los archivos 19 y 20 y a las capturas obtenidas.
