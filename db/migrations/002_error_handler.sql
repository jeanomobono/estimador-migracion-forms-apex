-- Migración 002: función de manejo de errores para la aplicación APEX
-- Ejecutar como usuario ESTIMADOR contra FREEPDB1

CREATE OR REPLACE PACKAGE PKG_ERROR_HANDLER AS
    FUNCTION handle_error(p_error IN apex_error.t_error)
        RETURN apex_error.t_error_result;
END PKG_ERROR_HANDLER;
/

CREATE OR REPLACE PACKAGE BODY PKG_ERROR_HANDLER AS

    FUNCTION handle_error(p_error IN apex_error.t_error)
        RETURN apex_error.t_error_result
    IS
        l_result          apex_error.t_error_result;
        l_msg             VARCHAR2(4000);
        l_constraint_name VARCHAR2(255);
    BEGIN
        -- Valores por defecto: pasar el error sin modificar
        l_result.message          := p_error.message;
        l_result.additional_info  := p_error.additional_info;
        l_result.display_location := CASE
                                         WHEN p_error.is_internal_error
                                             THEN apex_error.c_on_error_page
                                         ELSE apex_error.c_inline_in_notification
                                     END;
        l_result.page_item_name   := p_error.page_item_name;
        l_result.column_alias     := p_error.column_alias;

        -- Solo interceptar errores de constraints de base de datos
        IF p_error.ora_sqlcode IN (-2290, -2292) THEN
            -- apex_error.t_error no expone constraint_name directamente;
            -- se extrae del mensaje ORA: "(SCHEMA.CONSTRAINT_NAME)"
            l_constraint_name := REGEXP_SUBSTR(p_error.ora_sqlerrm, '\((\w+)\.(\w+)\)', 1, 1, NULL, 2);
            l_msg := CASE l_constraint_name
                -- Check constraints — parámetros globales
                WHEN 'CK_PARAM_COMPLEJIDAD_HORAS'     THEN 'Las horas deben ser un número mayor a 0'
                WHEN 'CK_PARAM_ETAPA_CASE_PESO'       THEN 'El peso no puede ser negativo'
                WHEN 'CK_PARAM_ETAPA_CASE_RECUR'      THEN 'Los recursos paralelos deben ser un número mayor a 0'
                WHEN 'CK_PARAM_TIEMPO_ADIC_PCT'       THEN 'El porcentaje no puede ser negativo'
                -- Check constraints — parámetros snapshot por versión
                WHEN 'CK_EST_PARAM_COMPLEJIDAD_HORAS' THEN 'Las horas deben ser un número mayor a 0'
                WHEN 'CK_EST_PARAM_ETAPA_CASE_PESO'   THEN 'El peso no puede ser negativo'
                WHEN 'CK_EST_PARAM_ETAPA_CASE_RECUR'  THEN 'Los recursos paralelos deben ser un número mayor a 0'
                WHEN 'CK_EST_PARAM_TIEMPO_ADIC_PCT'   THEN 'El porcentaje no puede ser negativo'
                -- Check constraints — otras tablas
                WHEN 'CK_LINDET_CANTIDAD'             THEN 'La cantidad debe ser un número mayor a 0'
                WHEN 'CK_VERSIONES_EST_NUMERO'        THEN 'El número de versión debe ser mayor a 0'
                -- FK constraints — errores de integridad referencial
                WHEN 'FK_PROYECTOS_CLIENTE'           THEN 'No se puede eliminar el cliente porque tiene proyectos asociados'
                WHEN 'FK_CONTACTOS_CLIENTE'           THEN 'No se puede eliminar el cliente porque tiene contactos registrados. Eliminá los contactos primero.'
                WHEN 'FK_VERSIONES_EST_PROYECTO'      THEN 'No se puede eliminar el proyecto porque tiene versiones de estimación asociadas'
                WHEN 'FK_ELEMENTOS_VERSION'           THEN 'No se puede eliminar la versión porque tiene elementos de migración cargados'
                WHEN 'FK_LINDET_ELEMENTO'             THEN 'No se puede eliminar el elemento porque tiene líneas de detalle asociadas'
                WHEN 'FK_LINDET_PARAM_COMPLEJIDAD'    THEN 'No se puede eliminar este parámetro porque está en uso en estimaciones existentes'
                WHEN 'FK_EST_PARAM_COMPLEJIDAD_VER'   THEN 'No se puede eliminar la versión porque tiene parámetros de complejidad asociados'
                WHEN 'FK_EST_PARAM_ETAPA_CASE_VER'    THEN 'No se puede eliminar la versión porque tiene parámetros de etapa CASE asociados'
                WHEN 'FK_EST_PARAM_TIEMPO_ADIC_VER'   THEN 'No se puede eliminar la versión porque tiene parámetros de tiempo adicional asociados'
                ELSE NULL
            END;

            l_result.additional_info  := p_error.ora_sqlerrm;
            l_result.display_location := apex_error.c_inline_in_notification;

            IF l_msg IS NOT NULL THEN
                l_result.message := l_msg;
            ELSE
                l_result.message := 'Se produjo un error al guardar los datos. Por favor, revisá los valores ingresados e intentá de nuevo.';
            END IF;
        END IF;

        RETURN l_result;
    END handle_error;

END PKG_ERROR_HANDLER;
/
