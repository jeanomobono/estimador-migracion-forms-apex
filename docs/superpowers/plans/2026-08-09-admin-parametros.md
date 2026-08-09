# Admin de Parámetros — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir la página 100 de administración de parámetros globales con tres Interactive Grids de edición inline, incluyendo el DDL de soporte y la entrada de navegación.

**Architecture:** DDL first (ALTER TABLE + triggers BEFORE UPDATE), luego APEXlang para la página APEX con tres regiones IG independientes sobre las tablas de parámetros globales, y finalmente actualización de la lista de navegación. Cada IG usa DML automático de APEX sobre su tabla fuente. Los triggers de base de datos se encargan de setear `UPDATED_BY`/`UPDATED_AT` sin configuración adicional en APEX.

**Tech Stack:** Oracle Database 26 FREE, Oracle APEX 26, APEXlang (.apx), SQLcl MCP (`estimador_freepdb1`), Node.js 25 (apexctl.mjs para validación).

## Global Constraints

- Schema: `ESTIMADOR`, conexión sqlcl: `estimador_freepdb1`
- App directory: `estimador-migraciones-forms-apex/` (raíz del repo, no bajo `applications/`)
- Página nueva: número `100`, alias `ADMIN-PARAMETROS`
- Archivos APEXlang deben ser LF (`.gitattributes` ya lo enforce)
- Todos los `.apx` deben pasar `node tools/apexctl.mjs runtime validate` desde `.agents/skills/apex/apexlang/` antes de importar
- Sin agregar/eliminar filas en ningún IG (tipos y niveles son fijos)
- Toolbar de cada IG: solo `saveButton` (sin búsqueda, filtros, ni downloads)
- `UPDATED_BY`/`UPDATED_AT` se setean via trigger `BEFORE UPDATE`, no en APEX

---

## Mapa de archivos

| Archivo | Acción | Responsabilidad |
|---|---|---|
| `db/migrations/001_audit_parametros.sql` | Crear | ALTER TABLE + triggers BEFORE UPDATE en las 3 tablas |
| `estimador-migraciones-forms-apex/pages/p00100-admin-parametros.apx` | Crear | Página 100 con 3 regiones IG + 3 procesos ARP |
| `estimador-migraciones-forms-apex/shared-components/lists.apx` | Modificar | Agregar entrada "Parámetros" al navigation-menu |
| `estimador-migraciones-forms-apex/shared-components/breadcrumbs.apx` | Modificar | Agregar entrada breadcrumb para página 100 |

---

## Task 1: DDL — columnas de auditoría y triggers BEFORE UPDATE

**Files:**
- Create: `db/migrations/001_audit_parametros.sql`

**Interfaces:**
- Produces: columnas `UPDATED_BY VARCHAR2(255)` y `UPDATED_AT TIMESTAMP` en `PARAMETROS_COMPLEJIDAD`, `PARAMETROS_TIEMPO_ADICIONAL`, `PARAMETROS_ETAPA_CASE`; triggers `TRG_PARAM_COMPLEJIDAD_BU`, `TRG_PARAM_TIEMPO_ADIC_BU`, `TRG_PARAM_ETAPA_CASE_BU`

- [ ] **Step 1: Crear el archivo de migración**

Crear `db/migrations/001_audit_parametros.sql` con el siguiente contenido:

```sql
-- Migración 001: columnas de auditoría en tablas de parámetros globales
-- Ejecutar como usuario ESTIMADOR contra FREEPDB1

ALTER TABLE PARAMETROS_COMPLEJIDAD
    ADD (UPDATED_BY VARCHAR2(255), UPDATED_AT TIMESTAMP);

ALTER TABLE PARAMETROS_TIEMPO_ADICIONAL
    ADD (UPDATED_BY VARCHAR2(255), UPDATED_AT TIMESTAMP);

ALTER TABLE PARAMETROS_ETAPA_CASE
    ADD (UPDATED_BY VARCHAR2(255), UPDATED_AT TIMESTAMP);

CREATE OR REPLACE TRIGGER TRG_PARAM_COMPLEJIDAD_BU
BEFORE UPDATE ON PARAMETROS_COMPLEJIDAD
FOR EACH ROW
BEGIN
    :NEW.UPDATED_BY := SYS_CONTEXT('APEX$SESSION','APP_USER');
    :NEW.UPDATED_AT := SYSTIMESTAMP;
END;
/

CREATE OR REPLACE TRIGGER TRG_PARAM_TIEMPO_ADIC_BU
BEFORE UPDATE ON PARAMETROS_TIEMPO_ADICIONAL
FOR EACH ROW
BEGIN
    :NEW.UPDATED_BY := SYS_CONTEXT('APEX$SESSION','APP_USER');
    :NEW.UPDATED_AT := SYSTIMESTAMP;
END;
/

CREATE OR REPLACE TRIGGER TRG_PARAM_ETAPA_CASE_BU
BEFORE UPDATE ON PARAMETROS_ETAPA_CASE
FOR EACH ROW
BEGIN
    :NEW.UPDATED_BY := SYS_CONTEXT('APEX$SESSION','APP_USER');
    :NEW.UPDATED_AT := SYSTIMESTAMP;
END;
/
```

- [ ] **Step 2: Ejecutar la migración via sqlcl MCP**

Ejecutar cada sentencia contra `estimador_freepdb1` usando la tool `mcp__sqlcl__sql_run`. Ejecutar en orden: los tres ALTER TABLE primero, luego los tres CREATE OR REPLACE TRIGGER.

- [ ] **Step 3: Verificar que las columnas y triggers existen**

```sql
-- Verificar columnas
SELECT table_name, column_name, data_type
FROM user_tab_columns
WHERE table_name IN ('PARAMETROS_COMPLEJIDAD','PARAMETROS_TIEMPO_ADICIONAL','PARAMETROS_ETAPA_CASE')
  AND column_name IN ('UPDATED_BY','UPDATED_AT')
ORDER BY table_name, column_name;

-- Verificar triggers
SELECT trigger_name, table_name, status
FROM user_triggers
WHERE trigger_name IN ('TRG_PARAM_COMPLEJIDAD_BU','TRG_PARAM_TIEMPO_ADIC_BU','TRG_PARAM_ETAPA_CASE_BU')
ORDER BY trigger_name;
```

Resultado esperado: 6 filas de columnas (2 por tabla × 3 tablas) y 3 triggers con `STATUS = ENABLED`.

- [ ] **Step 4: Verificar trigger con UPDATE de prueba**

```sql
-- Test: trigger debe setear UPDATED_AT (UPDATED_BY queda NULL fuera de sesión APEX, es esperado)
UPDATE PARAMETROS_COMPLEJIDAD
   SET HORAS = HORAS
 WHERE ROWNUM = 1;

SELECT UPDATED_BY, UPDATED_AT FROM PARAMETROS_COMPLEJIDAD WHERE ROWNUM = 1;
ROLLBACK;
```

Resultado esperado: `UPDATED_AT` con timestamp reciente (UPDATED_BY puede ser NULL fuera de contexto APEX, lo que es correcto — el trigger usa SYS_CONTEXT que solo está disponible en sesión APEX).

- [ ] **Step 5: Commit**

```bash
git add db/migrations/001_audit_parametros.sql
git commit -m "feat: DDL auditoría — columnas UPDATED_BY/UPDATED_AT y triggers BEFORE UPDATE en tablas de parámetros"
```

---

## Task 2: APEXlang — página 100 con tres Interactive Grids

**Files:**
- Create: `estimador-migraciones-forms-apex/pages/p00100-admin-parametros.apx`

**Interfaces:**
- Consumes: tablas `PARAMETROS_COMPLEJIDAD`, `PARAMETROS_TIEMPO_ADICIONAL`, `PARAMETROS_ETAPA_CASE` con columnas `UPDATED_BY` y `UPDATED_AT` (producidas en Task 1)
- Produces: página APEX 100 importable con 3 IGs de edición inline

- [ ] **Step 1: Crear el archivo APEXlang de la página**

Crear `estimador-migraciones-forms-apex/pages/p00100-admin-parametros.apx`:

```apexlang
page 100 (
    name: Administración de Parámetros
    alias: ADMIN-PARAMETROS
    title: Parámetros del sistema
    appearance {
        pageTemplate: @/standard
        templateOptions: #DEFAULT#
    }
    navigation {
        cursorFocus: doNotFocusCursor
        breadcrumb {
            breadcrumb: @breadcrumb
            entry: @admin-parametros
        }
    }
    security {
        pageAccessProtection: argumentsMustHaveChecksum
        formAutoComplete: false
    }

    region ig-complejidad (
        name: Horas por nivel de complejidad
        type: interactiveGrid
        advanced {
            htmlDomId: ig_complejidad
        }
        layout {
            sequence: 10
            slot: BODY
        }
        appearance {
            template: @/standard
            templateOptions: #DEFAULT#
        }
        source {
            location: localDatabase
            type: sqlQuery
            sqlQuery:
                ```sql
                select
                    parametro_complejidad_id,
                    tipo_elemento,
                    nivel_complejidad,
                    horas,
                    updated_by,
                    updated_at
                from parametros_complejidad
                order by tipo_elemento, horas
                ```
        }
        edit {
            enabled: true
            allowedOperations: [
                update
            ]
        }
        pagination {
            type: none
        }
        messages {
            whenNoDataFound: Sin datos
        }
        toolbar {
            controls: [
                saveButton
            ]
        }

        column APEX$ROW_ACTION (
            type: actionsMenu
            layout {
                sequence: 10
            }
        )

        column PARAMETRO_COMPLEJIDAD_ID (
            type: hidden
            layout {
                sequence: 20
            }
            source {
                databaseColumn: PARAMETRO_COMPLEJIDAD_ID
                dataType: number
                primaryKey: true
            }
            exportPrinting {
                includeInExportPrint: false
            }
            enableUsersTo {
                sort: false
            }
        )

        column TIPO_ELEMENTO (
            type: display
            heading {
                heading: Tipo
            }
            layout {
                sequence: 30
            }
            source {
                databaseColumn: TIPO_ELEMENTO
                dataType: varchar2
            }
            enableUsersTo {
                sort: false
            }
        )

        column NIVEL_COMPLEJIDAD (
            type: display
            heading {
                heading: Nivel
            }
            layout {
                sequence: 40
            }
            source {
                databaseColumn: NIVEL_COMPLEJIDAD
                dataType: varchar2
            }
            enableUsersTo {
                sort: false
            }
        )

        column HORAS (
            type: numberField
            heading {
                heading: Horas
                alignment: end
            }
            layout {
                sequence: 50
                columnAlignment: end
            }
            source {
                databaseColumn: HORAS
                dataType: number
            }
            validation {
                valueRequired: true
            }
            enableUsersTo {
                sort: false
            }
        )

        column UPDATED_BY (
            type: display
            heading {
                heading: Último cambio por
            }
            layout {
                sequence: 60
            }
            source {
                databaseColumn: UPDATED_BY
                dataType: varchar2
            }
            enableUsersTo {
                sort: false
            }
        )

        column UPDATED_AT (
            type: display
            heading {
                heading: Fecha
            }
            layout {
                sequence: 70
            }
            source {
                databaseColumn: UPDATED_AT
                dataType: timestamp
            }
            enableUsersTo {
                sort: false
            }
        )
    )

    process ARP_COMPLEJIDAD (
        name: IG Complejidad - Guardar datos
        type: interactiveGridAutoRowProcessing
        editableRegion: @ig-complejidad
        execution {
            sequence: 10
        }
    )

    region ig-tiempo-adicional (
        name: Tiempos adicionales
        type: interactiveGrid
        advanced {
            htmlDomId: ig_tiempo_adicional
        }
        layout {
            sequence: 20
            slot: BODY
        }
        appearance {
            template: @/standard
            templateOptions: #DEFAULT#
        }
        source {
            location: localDatabase
            type: sqlQuery
            sqlQuery:
                ```sql
                select
                    parametro_tiempo_adicional_id,
                    concepto,
                    base_calculo,
                    porcentaje,
                    updated_by,
                    updated_at
                from parametros_tiempo_adicional
                order by orden
                ```
        }
        edit {
            enabled: true
            allowedOperations: [
                update
            ]
        }
        pagination {
            type: none
        }
        messages {
            whenNoDataFound: Sin datos
        }
        toolbar {
            controls: [
                saveButton
            ]
        }

        column APEX$ROW_ACTION (
            type: actionsMenu
            layout {
                sequence: 10
            }
        )

        column PARAMETRO_TIEMPO_ADICIONAL_ID (
            type: hidden
            layout {
                sequence: 20
            }
            source {
                databaseColumn: PARAMETRO_TIEMPO_ADICIONAL_ID
                dataType: number
                primaryKey: true
            }
            exportPrinting {
                includeInExportPrint: false
            }
            enableUsersTo {
                sort: false
            }
        )

        column CONCEPTO (
            type: display
            heading {
                heading: Concepto
            }
            layout {
                sequence: 30
            }
            source {
                databaseColumn: CONCEPTO
                dataType: varchar2
            }
            enableUsersTo {
                sort: false
            }
        )

        column BASE_CALCULO (
            type: display
            heading {
                heading: Base de cálculo
            }
            layout {
                sequence: 40
            }
            source {
                databaseColumn: BASE_CALCULO
                dataType: varchar2
            }
            enableUsersTo {
                sort: false
            }
        )

        column PORCENTAJE (
            type: numberField
            heading {
                heading: Porcentaje (%)
                alignment: end
            }
            layout {
                sequence: 50
                columnAlignment: end
            }
            source {
                databaseColumn: PORCENTAJE
                dataType: number
            }
            validation {
                valueRequired: true
            }
            enableUsersTo {
                sort: false
            }
        )

        column UPDATED_BY (
            type: display
            heading {
                heading: Último cambio por
            }
            layout {
                sequence: 60
            }
            source {
                databaseColumn: UPDATED_BY
                dataType: varchar2
            }
            enableUsersTo {
                sort: false
            }
        )

        column UPDATED_AT (
            type: display
            heading {
                heading: Fecha
            }
            layout {
                sequence: 70
            }
            source {
                databaseColumn: UPDATED_AT
                dataType: timestamp
            }
            enableUsersTo {
                sort: false
            }
        )
    )

    process ARP_TIEMPO_ADICIONAL (
        name: IG Tiempos Adicionales - Guardar datos
        type: interactiveGridAutoRowProcessing
        editableRegion: @ig-tiempo-adicional
        execution {
            sequence: 20
        }
    )

    region ig-etapa-case (
        name: Distribución por etapa CASE
        type: interactiveGrid
        advanced {
            htmlDomId: ig_etapa_case
        }
        layout {
            sequence: 30
            slot: BODY
        }
        appearance {
            template: @/standard
            templateOptions: #DEFAULT#
        }
        source {
            location: localDatabase
            type: sqlQuery
            sqlQuery:
                ```sql
                select
                    parametro_etapa_case_id,
                    etapa,
                    peso_porcentaje,
                    recursos_paralelos,
                    updated_by,
                    updated_at
                from parametros_etapa_case
                order by orden
                ```
        }
        edit {
            enabled: true
            allowedOperations: [
                update
            ]
        }
        pagination {
            type: none
        }
        messages {
            whenNoDataFound: Sin datos
        }
        toolbar {
            controls: [
                saveButton
            ]
        }

        column APEX$ROW_ACTION (
            type: actionsMenu
            layout {
                sequence: 10
            }
        )

        column PARAMETRO_ETAPA_CASE_ID (
            type: hidden
            layout {
                sequence: 20
            }
            source {
                databaseColumn: PARAMETRO_ETAPA_CASE_ID
                dataType: number
                primaryKey: true
            }
            exportPrinting {
                includeInExportPrint: false
            }
            enableUsersTo {
                sort: false
            }
        )

        column ETAPA (
            type: display
            heading {
                heading: Etapa
            }
            layout {
                sequence: 30
            }
            source {
                databaseColumn: ETAPA
                dataType: varchar2
            }
            enableUsersTo {
                sort: false
            }
        )

        column PESO_PORCENTAJE (
            type: numberField
            heading {
                heading: Peso (%)
                alignment: end
            }
            layout {
                sequence: 40
                columnAlignment: end
            }
            source {
                databaseColumn: PESO_PORCENTAJE
                dataType: number
            }
            validation {
                valueRequired: true
            }
            enableUsersTo {
                sort: false
            }
        )

        column RECURSOS_PARALELOS (
            type: numberField
            heading {
                heading: Recursos paralelos
                alignment: end
            }
            layout {
                sequence: 50
                columnAlignment: end
            }
            source {
                databaseColumn: RECURSOS_PARALELOS
                dataType: number
            }
            validation {
                valueRequired: true
            }
            enableUsersTo {
                sort: false
            }
        )

        column UPDATED_BY (
            type: display
            heading {
                heading: Último cambio por
            }
            layout {
                sequence: 60
            }
            source {
                databaseColumn: UPDATED_BY
                dataType: varchar2
            }
            enableUsersTo {
                sort: false
            }
        )

        column UPDATED_AT (
            type: display
            heading {
                heading: Fecha
            }
            layout {
                sequence: 70
            }
            source {
                databaseColumn: UPDATED_AT
                dataType: timestamp
            }
            enableUsersTo {
                sort: false
            }
        )
    )

    process ARP_ETAPA_CASE (
        name: IG Etapas CASE - Guardar datos
        type: interactiveGridAutoRowProcessing
        editableRegion: @ig-etapa-case
        execution {
            sequence: 30
        }
    )

)
```

- [ ] **Step 2: Validar el .apx con apexctl**

Desde la raíz del repo, ejecutar:

```bash
node .agents/skills/apex/apexlang/tools/apexctl.mjs runtime validate \
  --app-path "$(pwd)/estimador-migraciones-forms-apex" \
  --db-connection-name estimador_freepdb1
```

Resultado esperado: sin errores de gramática ni de runtime. Si hay errores, leer `validation-report.json` en el directorio de output y corregir el `.apx` antes de continuar.

- [ ] **Step 3: Commit del .apx**

```bash
git add estimador-migraciones-forms-apex/pages/p00100-admin-parametros.apx
git commit -m "feat: página 100 admin de parámetros — 3 Interactive Grids con edición inline"
```

---

## Task 3: Navegación y breadcrumb

**Files:**
- Modify: `estimador-migraciones-forms-apex/shared-components/lists.apx`
- Modify: `estimador-migraciones-forms-apex/shared-components/breadcrumbs.apx`

**Interfaces:**
- Consumes: página 100 existente (producida en Task 2)
- Produces: entrada "Parámetros" en el menú lateral; breadcrumb "Parámetros" en página 100

- [ ] **Step 1: Agregar entrada al navigation-menu en lists.apx**

En `estimador-migraciones-forms-apex/shared-components/lists.apx`, dentro del bloque `list navigation-menu (...)`, agregar después de la entrada `home`:

```apexlang
    entry parametros (
        label: Parámetros
        icon {
            imageIconCssClasses: fa-sliders
        }
        layout {
            sequence: 20
        }
        link {
            target: {
                page: 100
            }
        }
    )
```

- [ ] **Step 2: Agregar entrada al breadcrumb en breadcrumbs.apx**

En `estimador-migraciones-forms-apex/shared-components/breadcrumbs.apx`, dentro del bloque `breadcrumb breadcrumb (...)`, agregar después de la entrada `home`:

```apexlang
    entry admin-parametros (
        name: Parámetros
        pageNumber: 100
        execution {
            sequence: 20
        }
        link {
            target: {
                page: 100
            }
        }
    )
```

- [ ] **Step 3: Validar los shared-components con apexctl**

```bash
node .agents/skills/apex/apexlang/tools/apexctl.mjs runtime validate \
  --app-path "$(pwd)/estimador-migraciones-forms-apex" \
  --db-connection-name estimador_freepdb1
```

Resultado esperado: sin errores.

- [ ] **Step 4: Commit**

```bash
git add estimador-migraciones-forms-apex/shared-components/lists.apx \
        estimador-migraciones-forms-apex/shared-components/breadcrumbs.apx
git commit -m "feat: entrada Parámetros en navegación y breadcrumb para página 100"
```

---

## Task 4: Import a APEX y verificación funcional

**Files:**
- (ningún archivo nuevo — import via sqlcl al workspace APEX)

**Interfaces:**
- Consumes: todos los `.apx` validados de Tasks 2 y 3

- [ ] **Step 1: Importar la app actualizada via sqlcl**

Usando la tool `mcp__sqlcl__sqlcl_run` contra `estimador_freepdb1`:

```sql
apex import -application-id 100 -dir estimador-migraciones-forms-apex -db-connection-name estimador_freepdb1
```

O via el comando APEXlang:

```bash
node .agents/skills/apex/apexlang/tools/apexctl.mjs runtime validate \
  --app-path "$(pwd)/estimador-migraciones-forms-apex" \
  --db-connection-name estimador_freepdb1 \
  --import
```

- [ ] **Step 2: Verificar en el browser**

Navegar a la app APEX (app id 100), iniciar sesión, ir a "Parámetros" en el menú lateral.

Checklist de verificación:
- [ ] La página carga sin errores ORA- ni APEX-
- [ ] IG 1 muestra 16 filas (4 tipos × 5 niveles + MENU) con TIPO_ELEMENTO y NIVEL_COMPLEJIDAD no editables
- [ ] IG 2 muestra 5 filas (conceptos de tiempo adicional) con CONCEPTO y BASE_CALCULO no editables
- [ ] IG 3 muestra 5 filas (etapas CASE) con ETAPA no editable
- [ ] Editar un valor numérico en cualquier IG → guardar → el valor persiste al recargar
- [ ] Después de guardar, UPDATED_BY muestra el usuario APEX logueado y UPDATED_AT la fecha/hora del cambio
- [ ] El breadcrumb muestra "Home > Parámetros"
- [ ] No hay botones de agregar ni eliminar filas en ningún IG

- [ ] **Step 3: Commit final si se hicieron ajustes de importación**

```bash
git add -A
git commit -m "feat: import página 100 a APEX — módulo admin de parámetros completo"
```
