-- Migración 005: trigger BEFORE INSERT en CONTACTOS_CLIENTE
-- Pobla CLIENTE_ID desde el session state de APEX cuando el ARP del IG
-- no puede setearlo (las columnas hidden de IG no admiten default en APEXlang).
-- APEX_UTIL.GET_SESSION_STATE funciona dentro del contexto de una request APEX.
-- Ejecutar como usuario ESTIMADOR contra FREEPDB1

CREATE OR REPLACE TRIGGER TRG_CONTACTOS_CLIENTE_BI
BEFORE INSERT ON CONTACTOS_CLIENTE
FOR EACH ROW
BEGIN
    IF :NEW.CLIENTE_ID IS NULL THEN
        :NEW.CLIENTE_ID := TO_NUMBER(APEX_UTIL.GET_SESSION_STATE('P201_CLIENTE_ID'));
    END IF;
END;
/
