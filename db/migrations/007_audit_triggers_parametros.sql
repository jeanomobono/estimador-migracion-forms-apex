-- Migration 007: triggers de auditoría BEFORE UPDATE en tablas de parámetros
--
-- Popula UPDATED_BY y UPDATED_AT al guardar cambios desde la página p00100.
-- sys_context('APEX$SESSION','APP_USER') devuelve el usuario autenticado APEX.
--
-- Ejecutar como usuario ESTIMADOR contra FREEPDB1

CREATE OR REPLACE TRIGGER estimador.trg_parametros_complejidad_bu
BEFORE UPDATE ON estimador.parametros_complejidad
FOR EACH ROW
BEGIN
    :new.updated_by := sys_context('APEX$SESSION', 'APP_USER');
    :new.updated_at := systimestamp;
END;
/

CREATE OR REPLACE TRIGGER estimador.trg_parametros_tiempo_adicional_bu
BEFORE UPDATE ON estimador.parametros_tiempo_adicional
FOR EACH ROW
BEGIN
    :new.updated_by := sys_context('APEX$SESSION', 'APP_USER');
    :new.updated_at := systimestamp;
END;
/

CREATE OR REPLACE TRIGGER estimador.trg_parametros_etapa_case_bu
BEFORE UPDATE ON estimador.parametros_etapa_case
FOR EACH ROW
BEGIN
    :new.updated_by := sys_context('APEX$SESSION', 'APP_USER');
    :new.updated_at := systimestamp;
END;
/
