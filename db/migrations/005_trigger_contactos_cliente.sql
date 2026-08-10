-- Migración 005: package de contexto + trigger BEFORE INSERT en CONTACTOS_CLIENTE
--
-- Problema: las columnas hidden de IG no admiten `default` block en APEXlang.
-- El ARP inserta NULL en CLIENTE_ID y ORDEN para filas nuevas.
--
-- Solución (patrón "package global" de Oracle):
--   1. PKG_APEX_CONTEXT.g_cliente_id se setea desde un proceso APEX (seq 15)
--      que corre ANTES del ARP (seq 20) en la misma sesión de DB.
--   2. El trigger lee esa variable de package (siempre disponible en la misma sesión).
--   3. ORDEN usa DEFAULT 10 cuando llega NULL (el DEFAULT de la tabla solo aplica
--      si la columna se omite del INSERT; si el ARP envía NULL explícito, el trigger
--      es necesario).
--
-- Ejecutar como usuario ESTIMADOR contra FREEPDB1

CREATE OR REPLACE PACKAGE PKG_APEX_CONTEXT AS
    g_cliente_id NUMBER;
END PKG_APEX_CONTEXT;
/

CREATE OR REPLACE TRIGGER TRG_CONTACTOS_CLIENTE_BI
BEFORE INSERT ON CONTACTOS_CLIENTE
FOR EACH ROW
BEGIN
    IF :NEW.CLIENTE_ID IS NULL THEN
        :NEW.CLIENTE_ID := PKG_APEX_CONTEXT.g_cliente_id;
    END IF;
    IF :NEW.ORDEN IS NULL THEN
        :NEW.ORDEN := 10;
    END IF;
END;
/
