-- Migration 008: trigger de auditoría para VERSIONES_ESTIMACION
CREATE OR REPLACE TRIGGER estimador.trg_versiones_estimacion_bu
BEFORE UPDATE ON estimador.versiones_estimacion
FOR EACH ROW
BEGIN
    :new.updated_by := sys_context('APEX$SESSION', 'APP_USER');
    :new.updated_at := systimestamp;
END;
/
