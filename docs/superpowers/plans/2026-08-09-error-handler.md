# Manejo de Errores a Nivel de Aplicación — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Traducir errores de Oracle (check constraints y FK violations) a mensajes en español legibles para el usuario, aplicado automáticamente a toda la aplicación APEX.

**Architecture:** Un package PL/SQL (`ESTIMADOR.PKG_ERROR_HANDLER`) con una función de firma `apex_error.t_error → apex_error.t_error_result` registrada como error handling function de la app. La función intercepta errores ORA-2290 (check) y ORA-2292 (FK) y devuelve mensajes amigables mapeados por nombre de constraint; los errores no mapeados caen en un fallback genérico.

**Tech Stack:** Oracle PL/SQL, Oracle APEX 26 (`apex_error` API), APEXlang (.apx), sqlcl MCP (`estimador_freepdb1`).

## Global Constraints

- Schema: `ESTIMADOR`, base de datos: Oracle 26 FREE, instancia: `FREEPDB1`
- App APEX id: 100, workspace: `APPS`
- Conexión sqlcl MCP: `estimador_freepdb1`
- Artefactos APEXlang en `estimador-migraciones-forms-apex/` — todo cambio a la app se versiona ahí
- Import APEX requiere workaround: copiar la app a dir temporal sin `workspace-components/` y sin el bloque `genAI` en `application.apx` (ver Task 2)
- Spec completo en `docs/superpowers/specs/2026-08-09-error-handler-design.md`

---

### Task 1: DDL — Package PKG_ERROR_HANDLER

**Files:**
- Create: `db/migrations/002_error_handler.sql`

**Interfaces:**
- Produces: `ESTIMADOR.PKG_ERROR_HANDLER.handle_error` — función pública que Task 2 registra en la app

- [ ] **Step 1: Crear el archivo de migración**

Crear `db/migrations/002_error_handler.sql` con el siguiente contenido exacto:

```sql
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
        l_result apex_error.t_error_result;
        l_msg    VARCHAR2(4000);
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
            l_msg := CASE p_error.constraint_name
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
```

- [ ] **Step 2: Ejecutar la migración via sqlcl MCP**

Usar `mcp__sqlcl__sql_run` para ejecutar el contenido del archivo contra la conexión `estimador_freepdb1`. Ejecutar el spec del package primero, luego el body (o ejecutar ambos en una sola llamada si el MCP lo permite con el separador `/`).

- [ ] **Step 3: Verificar que el package compiló sin errores**

```sql
SELECT object_name, object_type, status
FROM user_objects
WHERE object_name = 'PKG_ERROR_HANDLER'
ORDER BY object_type
```

Resultado esperado: dos filas — `PACKAGE` y `PACKAGE BODY`, ambas con `status = VALID`.

Si alguna tiene status `INVALID`, consultar errores:
```sql
SELECT line, position, text FROM user_errors WHERE name = 'PKG_ERROR_HANDLER' ORDER BY sequence
```

- [ ] **Step 4: Commit**

```bash
git add db/migrations/002_error_handler.sql
git commit -m "Agregar package PKG_ERROR_HANDLER para manejo de errores APEX"
```

---

### Task 2: APEX — Registrar función de manejo de errores e importar

**Files:**
- Modify: `estimador-migraciones-forms-apex/application.apx` (agregar bloque `errorHandling`)

**Interfaces:**
- Consumes: `ESTIMADOR.PKG_ERROR_HANDLER.handle_error` (creada en Task 1)

- [ ] **Step 1: Agregar bloque `errorHandling` en application.apx**

En `estimador-migraciones-forms-apex/application.apx`, agregar el bloque `errorHandling` después del bloque `runtime { ... }` y antes del bloque `substitution`:

```apexlang
    errorHandling {
        errorHandlingFunction: ESTIMADOR.PKG_ERROR_HANDLER.handle_error
    }
```

El archivo resultante debe verse así en esa sección:

```apexlang
    runtime {
        allowFeedback: true
    }

    errorHandling {
        errorHandlingFunction: ESTIMADOR.PKG_ERROR_HANDLER.handle_error
    }

    substitution APP_NAME (
```

- [ ] **Step 2: Preparar directorio temporal para el import**

El import requiere un workaround porque `workspace-components/generative-ai-services/claude-opus-5.apx` usa un provider no estándar que falla la validación. Pasos:

```bash
# Limpiar y recrear el directorio temporal
rm -rf /tmp/apex-import-100
mkdir /tmp/apex-import-100

# Copiar todo excepto workspace-components
cp -r estimador-migraciones-forms-apex/application.apx \
      estimador-migraciones-forms-apex/page-groups.apx \
      estimador-migraciones-forms-apex/pages \
      estimador-migraciones-forms-apex/shared-components \
      estimador-migraciones-forms-apex/deployments \
      estimador-migraciones-forms-apex/.apex \
      /tmp/apex-import-100/

# Eliminar el bloque genAI de la copia temporal de application.apx
# (el bloque `genAI { service: @claude-opus-5 }` en líneas 3-5 del archivo original)
# Usar Python o sed para quitar esas líneas de /tmp/apex-import-100/application.apx
```

Para quitar el bloque genAI del archivo temporal usar Python:
```python
import re
content = open('/tmp/apex-import-100/application.apx').read()
content = re.sub(r'\s+genAI \{[^}]+\}', '', content)
open('/tmp/apex-import-100/application.apx', 'w').write(content)
```

- [ ] **Step 3: Importar via sqlcl MCP**

Usar `mcp__sqlcl__sqlcl_run` con ejecución ASYNCHRONOUS:

```
apex import -input /tmp/apex-import-100
```

Luego usar `mcp__sqlcl__request_status` para obtener el resultado.

Resultado esperado:
```
Importing application ID: 100 into workspace: APPS
Import successful.
```

- [ ] **Step 4: Verificar que la función quedó registrada en APEX**

```sql
SELECT error_handling_function
FROM apex_applications
WHERE application_id = 100
```

Resultado esperado: `ESTIMADOR.PKG_ERROR_HANDLER.handle_error`

- [ ] **Step 5: Commit**

```bash
git add estimador-migraciones-forms-apex/application.apx
git commit -m "Registrar función de manejo de errores en app APEX"
```

- [ ] **Step 6: Verificación manual en el browser**

Abrir la app APEX (app id 100), ir a página 100 (Administración de Parámetros), editar una celda de la grilla "Horas por nivel de complejidad" e ingresar `-1` en la columna Horas, y hacer clic en Guardar.

Resultado esperado: aparece la notificación "Las horas deben ser un número mayor a 0" (no un ORA-02290 crudo).
