-- Migración 006: eliminar package y trigger de contexto (ya no necesarios)
--
-- El proceso ARP del IG de contactos ahora usa custom PL/SQL (targetType: plsqlCode)
-- con :P201_CLIENTE_ID directamente en el INSERT, reemplazando el patrón
-- package global + trigger de la migración 005.
--
-- Ejecutar como usuario ESTIMADOR contra FREEPDB1

DROP TRIGGER ESTIMADOR.TRG_CONTACTOS_CLIENTE_BI;
DROP PACKAGE ESTIMADOR.PKG_APEX_CONTEXT;
