# Módulo de Estimaciones — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir el módulo de estimaciones: p220 (lista de versiones por proyecto) y p221 (detalle con IGs master-detail de elementos y líneas, más resumen calculado), incluyendo la navigation desde p210.

**Architecture:** Tres páginas APEXlang nuevas/modificadas + un trigger de auditoría. La creación de versión dispara un snapshot de los tres parámetros globales. El IG de líneas usa el patrón nativo `masterDetail` de APEX (sin dynamic actions). El resumen se calcula con un Classic Report SQL usando CTEs que aplican `BASE_CALCULO` de cada tiempo adicional.

**Tech Stack:** Oracle APEX 26 / APEXlang (.apx), Oracle Database 26 FREE, schema `ESTIMADOR`, conexión MCP `estimador_freepdb1`, Node.js v25 (apexctl CLI), SQLcl 26.1.2+.

## Global Constraints

- Nunca pedir credenciales por chat — usar siempre la conexión MCP `estimador_freepdb1`
- Slot names en minúsculas: `body`, `breadcrumbBar`, `regionBody`, `rightOfInteractiveReportSearchBar`
- Todo IG editable requiere `APEX$ROW_ACTION` (type: actionsMenu), `APEX$ROW_SELECTOR` (type: rowSelector) y `savedReport` con `displayColumn` cubriendo TODAS las columnas
- INSERT con columna IDENTITY: siempre `RETURNING pk INTO :PK_BIND` en el DML custom PL/SQL
- Import al Builder: `rsync --exclude='workspace-components'` + `apex import -workspaceid 2730067880198645 -id 100`
- `pageItemsToSubmit: ITEM` (scalar, sin corchetes) cuando hay un solo item

---

## Archivos a crear o modificar

| Acción | Archivo |
|--------|---------|
| Crear | `db/migrations/008_trigger_versiones_estimacion.sql` |
| Crear | `estimador-migraciones-forms-apex/pages/p00220-versiones-estimacion.apx` |
| Crear | `estimador-migraciones-forms-apex/pages/p00221-detalle-version.apx` |
| Modificar | `estimador-migraciones-forms-apex/pages/p00210-proyectos-cliente.apx` |

---

## Task 1: Migration 008 — Trigger de auditoría en VERSIONES_ESTIMACION

**Files:**
- Create: `db/migrations/008_trigger_versiones_estimacion.sql`

**Interfaces:**
- Consumes: tabla `estimador.versiones_estimacion` (ya existe con columnas `updated_by VARCHAR2(255)`, `updated_at TIMESTAMP(6)`)
- Produces: trigger activo que auto-completa auditoría en UPDATE

- [ ] **Step 1: Crear el archivo de migración**

Crear `db/migrations/008_trigger_versiones_estimacion.sql` con:

```sql
-- Migration 008: trigger de auditoría para VERSIONES_ESTIMACION
CREATE OR REPLACE TRIGGER estimador.trg_versiones_estimacion_bu
BEFORE UPDATE ON estimador.versiones_estimacion
FOR EACH ROW
BEGIN
    :new.updated_by := sys_context('APEX$SESSION', 'APP_USER');
    :new.updated_at := systimestamp;
END;
/
```

- [ ] **Step 2: Ejecutar via MCP sqlcl**

Usar la herramienta `mcp__sqlcl__sql_run` con la conexión `estimador_freepdb1`:

```sql
CREATE OR REPLACE TRIGGER estimador.trg_versiones_estimacion_bu
BEFORE UPDATE ON estimador.versiones_estimacion
FOR EACH ROW
BEGIN
    :new.updated_by := sys_context('APEX$SESSION', 'APP_USER');
    :new.updated_at := systimestamp;
END;
/
```

Verificar: respuesta debe ser `Trigger TRG_VERSIONES_ESTIMACION_BU compiled`.

- [ ] **Step 3: Verificar trigger existente**

```sql
SELECT trigger_name, status, trigger_type
FROM all_triggers
WHERE owner = 'ESTIMADOR' AND table_name = 'VERSIONES_ESTIMACION'
```

Esperado: 1 fila, `STATUS = ENABLED`.

- [ ] **Step 4: Commit**

```bash
git add db/migrations/008_trigger_versiones_estimacion.sql
git commit -m "feat: trigger auditoría BEFORE UPDATE en VERSIONES_ESTIMACION"
```

---

## Task 2: Crear p220 — Lista de versiones de estimación

**Files:**
- Create: `estimador-migraciones-forms-apex/pages/p00220-versiones-estimacion.apx`

**Interfaces:**
- Consumes: `P220_PROYECTO_ID`, `P220_CLIENTE_ID` (pasados como items desde p210)
- Produces: IR de versiones + proceso de creación → session state `P221_VERSION_ESTIMACION_ID`, `P221_PROYECTO_ID` → redirige a p221

- [ ] **Step 1: Crear el archivo APEXlang**

Crear `estimador-migraciones-forms-apex/pages/p00220-versiones-estimacion.apx`:

```apexlang
page 220 (
    name: Versiones de estimación
    alias: VERSIONES-ESTIMACION
    title: Versiones de estimación
    appearance {
        pageTemplate: @/standard
        templateOptions: #DEFAULT#
    }
    navigation {
        cursorFocus: doNotFocusCursor
    }
    security {
        pageAccessProtection: argumentsMustHaveChecksum
        formAutoComplete: false
    }

    region breadcrumb-versiones (
        name: Versiones
        type: breadcrumb
        source {
            breadcrumb: @breadcrumb
        }
        layout {
            sequence: 10
            slot: breadcrumbBar
        }
        appearance {
            template: @/title-bar
            templateOptions: #DEFAULT#
        }
        componentAppearance {
            breadcrumbTemplate: @/breadcrumb
            templateOptions: #DEFAULT#
        }
    )

    region ir-versiones (
        name: Versiones de estimación
        type: interactiveReport
        source {
            location: localDatabase
            type: sqlQuery
            sqlQuery:
                ```sql
                select
                    v.version_estimacion_id,
                    v.numero_version,
                    v.created_by,
                    v.created_at
                from versiones_estimacion v
                where v.proyecto_id = :P220_PROYECTO_ID
                order by v.numero_version
                ```
            pageItemsToSubmit: P220_PROYECTO_ID
        }
        layout {
            sequence: 20
            slot: body
        }
        appearance {
            template: @/interactive-report
            templateOptions: #DEFAULT#
        }
        link {
            linkColumn: customTarget
            target: {
                page: 221
                items: {
                    P221_VERSION_ESTIMACION_ID: #VERSION_ESTIMACION_ID#
                    P221_PROYECTO_ID: #P220_PROYECTO_ID#
                }
                clearCache: 221
            }
            linkIcon: <span role="img" aria-label="Ver detalle" class="fa fa-table-rows" title="Ver detalle"></span>
        }
        messages {
            whenNoDataFound: No hay versiones para este proyecto. Haga clic en «Nueva versión» para crear la primera.
        }

        column VERSION_ESTIMACION_ID (
            type: hidden
            heading {
                heading: ID
            }
            layout {
                sequence: 10
            }
            source {
                dataType: NUMBER
            }
            advanced {
                endUserAlias: A
            }
        )

        column NUMERO_VERSION (
            type: plainText
            heading {
                heading: Versión
            }
            layout {
                sequence: 20
            }
            source {
                dataType: NUMBER
            }
            advanced {
                endUserAlias: B
            }
        )

        column CREATED_BY (
            type: plainText
            heading {
                heading: Creado por
            }
            layout {
                sequence: 30
            }
            source {
                dataType: STRING
            }
            advanced {
                endUserAlias: C
            }
        )

        column CREATED_AT (
            type: plainText
            heading {
                heading: Fecha creación
            }
            layout {
                sequence: 40
            }
            appearance {
                formatMask: DD/MM/YYYY HH24:MI
            }
            source {
                dataType: DATE
            }
            advanced {
                endUserAlias: D
            }
        )

        savedReport PRIMARY (
            visibility: primaryDefault
            view {
                rowsPerPage: 15
            }
        )

    )

    pageItem P220_PROYECTO_ID (
        type: hidden
        layout {
            sequence: 10
            region: @ir-versiones
            slot: regionBody
        }
        security {
            sessionStateProtection: checksumRequiredSessionLevel
        }
    )

    pageItem P220_CLIENTE_ID (
        type: hidden
        layout {
            sequence: 20
            region: @ir-versiones
            slot: regionBody
        }
    )

    button nueva-version (
        buttonName: NUEVA_VERSION
        label: Nueva versión
        layout {
            sequence: 10
            region: @ir-versiones
            slot: rightOfInteractiveReportSearchBar
        }
        appearance {
            buttonTemplate: @/text-with-icon
            hot: true
            templateOptions: [
                #DEFAULT#
                t-Button--iconLeft
            ]
            icon: fa-plus
        }
        behavior {
            action: submit
        }
    )

    process crear-version (
        name: Crear nueva versión con snapshot de parámetros
        type: executeCode
        source {
            plsqlCode:
                ```plsql
                declare
                  l_version_id number;
                  l_num        number;
                begin
                  select nvl(max(numero_version), 0) + 1
                  into l_num
                  from versiones_estimacion
                  where proyecto_id = :P220_PROYECTO_ID;

                  insert into versiones_estimacion (proyecto_id, numero_version, created_by, created_at)
                  values (:P220_PROYECTO_ID, l_num, :APP_USER, systimestamp)
                  returning version_estimacion_id into l_version_id;

                  insert into estimacion_parametros_complejidad
                    (version_estimacion_id, tipo_elemento, nivel_complejidad, horas)
                  select l_version_id, tipo_elemento, nivel_complejidad, horas
                  from parametros_complejidad;

                  insert into estimacion_parametros_tiempo_adicional
                    (version_estimacion_id, concepto, base_calculo, porcentaje, orden)
                  select l_version_id, concepto, base_calculo, porcentaje, orden
                  from parametros_tiempo_adicional;

                  insert into estimacion_parametros_etapa_case
                    (version_estimacion_id, etapa, orden, peso_porcentaje, recursos_paralelos)
                  select l_version_id, etapa, orden, peso_porcentaje, recursos_paralelos
                  from parametros_etapa_case;

                  :P221_VERSION_ESTIMACION_ID := l_version_id;
                  :P221_PROYECTO_ID            := :P220_PROYECTO_ID;
                end;
                ```
        }
        execution {
            sequence: 10
        }
        serverSideCondition {
            type: requestIsContainedInValue
            value: NUEVA_VERSION
        }
    )

    branch (
        name: Ir a detalle de versión nueva
        execution {
            sequence: 10
        }
        behavior {
            type: page
            pageNumber: 221
        }
        serverSideCondition {
            type: requestIsContainedInValue
            value: NUEVA_VERSION
        }
    )

    dynamicAction refresh-after-modal (
        name: Actualizar lista de versiones
        execution {
            sequence: 10
        }
        when {
            event: apexafterclosedialog
            selectionType: region
            region: @ir-versiones
        }

        action refresh-ir-versiones (
            action: refresh
            affectedElements {
                selectionType: region
                region: @ir-versiones
            }
            execution {
                sequence: 10
                fireOnInit: false
            }
        )

    )

)
```

- [ ] **Step 2: Importar al Builder y verificar parseo**

```bash
rm -rf /tmp/apex-import-220 && \
rsync -a --exclude='workspace-components' \
  /home/jean/projects/estimador-migracion/estimador-migraciones-forms-apex/ \
  /tmp/apex-import-220/
```

Luego via MCP sqlcl:
```
apex import -input /tmp/apex-import-220 -workspaceid 2730067880198645 -id 100
```

Verificar: no errores en la salida. Abrir la app en el Builder (app 100) y confirmar que p220 aparece en el árbol de páginas.

- [ ] **Step 3: Verificar flujo básico desde navegador**

1. Ir a p210 de cualquier cliente con proyectos
2. Navegar manualmente a `f?p=100:220` con `P220_PROYECTO_ID` de un proyecto existente
3. Confirmar que el IR muestra "No hay versiones..." si no hay datos
4. Hacer clic en "Nueva versión" — debe crear la versión y redirigir a p221 (p221 aún estará vacía, está bien)
5. Verificar en DB que se crearon los snapshots:

```sql
SELECT v.version_estimacion_id, v.numero_version,
       (SELECT COUNT(*) FROM estimacion_parametros_complejidad WHERE version_estimacion_id = v.version_estimacion_id) comp,
       (SELECT COUNT(*) FROM estimacion_parametros_tiempo_adicional WHERE version_estimacion_id = v.version_estimacion_id) tad,
       (SELECT COUNT(*) FROM estimacion_parametros_etapa_case WHERE version_estimacion_id = v.version_estimacion_id) etapa
FROM versiones_estimacion v
ORDER BY v.version_estimacion_id DESC
FETCH FIRST 3 ROWS ONLY
```

Esperado: comp=16, tad=5, etapa=5 por versión.

- [ ] **Step 4: Exportar y sincronizar repo**

Via MCP sqlcl:
```
apex export -applicationid 100 -expType APEXLANG -dir /tmp/apex-export-220
```

```bash
rsync -a --exclude='workspace-components' \
  /tmp/apex-export-220/ \
  /home/jean/projects/estimador-migracion/estimador-migraciones-forms-apex/
```

- [ ] **Step 5: Commit**

```bash
git add estimador-migraciones-forms-apex/pages/p00220-versiones-estimacion.apx
git add estimador-migraciones-forms-apex/  # cualquier otro archivo actualizado por el export
git commit -m "feat: p220 lista de versiones de estimación con proceso de creación + snapshot"
```

---

## Task 3: Crear p221 — IG Elementos (master)

**Files:**
- Create: `estimador-migraciones-forms-apex/pages/p00221-detalle-version.apx`

**Interfaces:**
- Consumes: `P221_VERSION_ESTIMACION_ID` (session state, set por p220), `P221_PROYECTO_ID`
- Produces: IG editable sobre tabla `ELEMENTOS`, con `htmlDomId: ig_elementos` para que el IG de líneas pueda referenciarlo como master

- [ ] **Step 1: Crear el archivo APEXlang con la estructura base y el IG Elementos**

Crear `estimador-migraciones-forms-apex/pages/p00221-detalle-version.apx`:

```apexlang
page 221 (
    name: Detalle de versión
    alias: DETALLE-VERSION
    title: Detalle de versión
    appearance {
        pageTemplate: @/standard
        templateOptions: #DEFAULT#
    }
    navigation {
        cursorFocus: doNotFocusCursor
    }
    security {
        pageAccessProtection: argumentsMustHaveChecksum
        formAutoComplete: false
    }

    region breadcrumb-detalle-version (
        name: Detalle de versión
        type: breadcrumb
        source {
            breadcrumb: @breadcrumb
        }
        layout {
            sequence: 10
            slot: breadcrumbBar
        }
        appearance {
            template: @/title-bar
            templateOptions: #DEFAULT#
        }
        componentAppearance {
            breadcrumbTemplate: @/breadcrumb
            templateOptions: #DEFAULT#
        }
    )

    region ig-elementos (
        name: Elementos
        type: interactiveGrid
        source {
            location: localDatabase
            type: sqlQuery
            sqlQuery:
                ```sql
                select elemento_id, version_estimacion_id, nombre
                from elementos
                where version_estimacion_id = :P221_VERSION_ESTIMACION_ID
                order by elemento_id
                ```
            pageItemsToSubmit: P221_VERSION_ESTIMACION_ID
        }
        layout {
            sequence: 10
            slot: body
        }
        appearance {
            template: @/interactive-report
            templateOptions: #DEFAULT#
        }
        advanced {
            htmlDomId: ig_elementos
        }
        edit {
            enabled: true
            deleteConfirmMessage: ¿Eliminar elemento y todas sus líneas de detalle?
        }
        toolbar {
            searchColumn: NOMBRE
        }

        column APEX$ROW_SELECTOR (
            type: rowSelector
            layout { sequence: 10 }
        )

        column APEX$ROW_ACTION (
            type: actionsMenu
            layout { sequence: 20 }
        )

        column ELEMENTO_ID (
            type: hidden
            heading { heading: ID }
            layout { sequence: 30 }
            source { databaseColumn: ELEMENTO_ID; dataType: number }
        )

        column VERSION_ESTIMACION_ID (
            type: hidden
            heading { heading: Version ID }
            layout { sequence: 40 }
            source { databaseColumn: VERSION_ESTIMACION_ID; dataType: number }
        )

        column NOMBRE (
            type: textField
            heading { heading: Elemento }
            layout { sequence: 50 }
            source { databaseColumn: NOMBRE; dataType: string }
            column {
                width: 400
            }
        )

        savedReport primary (
            visibility: primary
            view { default: grid }
            singleRowView { displayedColumns: true }
            displayColumn (
                column: @APEX$ROW_ACTION
                layout { sequence: 0 }
            )
            displayColumn (
                column: @ELEMENTO_ID
                layout { sequence: 10 }
            )
            displayColumn (
                column: @VERSION_ESTIMACION_ID
                layout { sequence: 20 }
            )
            displayColumn (
                column: @NOMBRE
                layout { sequence: 30 }
            )
        )

    )

    process elementos-save-interactive-grid-data (
        type: interactiveGridAutoRowProcessing
        editableRegion: @ig-elementos
        execution {
            sequence: 10
        }
        target {
            targetType: plsqlCode
            dmlPlsqlCode:
                ```plsql
                begin
                    case :APEX$ROW_STATUS
                    when 'C' then
                        insert into elementos (version_estimacion_id, nombre)
                        values (:P221_VERSION_ESTIMACION_ID, :NOMBRE)
                        returning elemento_id into :ELEMENTO_ID;
                    when 'U' then
                        update elementos set nombre = :NOMBRE
                        where elemento_id = :ELEMENTO_ID;
                    when 'D' then
                        delete from elementos where elemento_id = :ELEMENTO_ID;
                    end case;
                end;
                ```
        }
    )

    pageItem P221_VERSION_ESTIMACION_ID (
        type: hidden
        layout {
            sequence: 10
            region: @ig-elementos
            slot: regionBody
        }
        security {
            sessionStateProtection: checksumRequiredSessionLevel
        }
    )

    pageItem P221_PROYECTO_ID (
        type: hidden
        layout {
            sequence: 20
            region: @ig-elementos
            slot: regionBody
        }
    )

)
```

> **Nota:** el IG de líneas (Task 4) y el resumen (Task 4) se agregan a este mismo archivo antes del cierre del `page 221 (`.

- [ ] **Step 2: Importar y verificar IG Elementos**

```bash
rm -rf /tmp/apex-import-221 && \
rsync -a --exclude='workspace-components' \
  /home/jean/projects/estimador-migracion/estimador-migraciones-forms-apex/ \
  /tmp/apex-import-221/
```

Via MCP sqlcl: `apex import -input /tmp/apex-import-221 -workspaceid 2730067880198645 -id 100`

Verificar en el navegador:
1. Desde p220, hacer clic en el ícono de una versión existente → debe cargar p221
2. El IG Elementos debe renderizarse (vacío si la versión no tiene elementos aún)
3. Agregar un elemento: escribir un nombre, hacer clic en Save → fila debe persistir (RETURNING INTO garantiza que no desaparezca)
4. Verificar en DB: `SELECT * FROM estimador.elementos WHERE version_estimacion_id = <id>`

- [ ] **Step 3: Exportar y sincronizar** (igual que Task 2 Step 4)

---

## Task 4: Completar p221 — IG Líneas (master-detail) + Resumen

**Files:**
- Modify: `estimador-migraciones-forms-apex/pages/p00221-detalle-version.apx`

**Interfaces:**
- Consumes: static id `@ig-elementos` y columna `@ELEMENTO_ID` del master IG
- Produces: IG de líneas filtrado por elemento seleccionado; resumen calculado con horas totales

- [ ] **Step 1: Agregar IG Líneas al p221 (antes del cierre del `page 221 (`)**

Insertar en `p00221-detalle-version.apx`, después del bloque del process `elementos-save-interactive-grid-data` y antes de `pageItem P221_VERSION_ESTIMACION_ID`:

```apexlang
    region ig-lineas (
        name: Líneas de detalle
        type: interactiveGrid
        source {
            location: localDatabase
            type: sqlQuery
            sqlQuery:
                ```sql
                select
                    ld.linea_detalle_id,
                    ld.elemento_id,
                    ld.estimacion_param_complejidad_id,
                    ld.cantidad,
                    ld.cantidad * epc.horas as horas_total
                from lineas_detalle ld
                join estimacion_parametros_complejidad epc
                    on ld.estimacion_param_complejidad_id = epc.estimacion_param_complejidad_id
                ```
        }
        layout {
            sequence: 20
            slot: body
        }
        appearance {
            template: @/interactive-report
            templateOptions: #DEFAULT#
        }
        masterDetail {
            masterRegion: @ig-elementos
        }
        edit {
            enabled: true
        }

        column APEX$ROW_SELECTOR (
            type: rowSelector
            layout { sequence: 10 }
        )

        column APEX$ROW_ACTION (
            type: actionsMenu
            layout { sequence: 20 }
        )

        column LINEA_DETALLE_ID (
            type: hidden
            heading { heading: ID }
            layout { sequence: 30 }
            source { databaseColumn: LINEA_DETALLE_ID; dataType: number }
        )

        column ELEMENTO_ID (
            type: hidden
            heading { heading: Elemento ID }
            layout { sequence: 40 }
            source { databaseColumn: ELEMENTO_ID; dataType: number }
            masterDetail {
                masterColumn: @ELEMENTO_ID
            }
        )

        column ESTIMACION_PARAM_COMPLEJIDAD_ID (
            type: selectList
            heading { heading: Tipo / Nivel }
            layout { sequence: 50 }
            source { databaseColumn: ESTIMACION_PARAM_COMPLEJIDAD_ID; dataType: number }
            listOfValues {
                type: sqlQuery
                sqlQuery:
                    ```sql
                    select tipo_elemento || ' – ' || nvl(nivel_complejidad, '—') || '  (' || horas || ' h)' as d,
                           estimacion_param_complejidad_id as r
                    from estimacion_parametros_complejidad
                    where version_estimacion_id = :P221_VERSION_ESTIMACION_ID
                    order by tipo_elemento, horas
                    ```
                additionalValues: true
            }
            -- Nota: :P221_VERSION_ESTIMACION_ID es accesible en session state cuando la LOV se renderiza.
            -- Si el LOV no filtra (muestra todas las versiones mezcladas), agregar pageItemsToSubmit: P221_VERSION_ESTIMACION_ID
            -- en el source del ig-lineas.
        )

        column CANTIDAD (
            type: numberField
            heading { heading: Cantidad }
            layout { sequence: 60 }
            source { databaseColumn: CANTIDAD; dataType: number }
            defaultValue {
                type: static
                value: 1
            }
        )

        column HORAS_TOTAL (
            type: plainText
            heading { heading: Horas }
            layout { sequence: 70 }
            source { databaseColumn: HORAS_TOTAL; dataType: number }
            appearance { formatMask: FM9990.99 }
        )

        savedReport primary (
            visibility: primary
            view { default: grid }
            singleRowView { displayedColumns: true }
            displayColumn (
                column: @APEX$ROW_ACTION
                layout { sequence: 0 }
            )
            displayColumn (
                column: @LINEA_DETALLE_ID
                layout { sequence: 10 }
            )
            displayColumn (
                column: @ELEMENTO_ID
                layout { sequence: 20 }
            )
            displayColumn (
                column: @ESTIMACION_PARAM_COMPLEJIDAD_ID
                layout { sequence: 30 }
            )
            displayColumn (
                column: @CANTIDAD
                layout { sequence: 40 }
            )
            displayColumn (
                column: @HORAS_TOTAL
                layout { sequence: 50 }
            )
        )

    )

    process lineas-save-interactive-grid-data (
        type: interactiveGridAutoRowProcessing
        editableRegion: @ig-lineas
        execution {
            sequence: 20
        }
        target {
            targetType: plsqlCode
            dmlPlsqlCode:
                ```plsql
                begin
                    case :APEX$ROW_STATUS
                    when 'C' then
                        insert into lineas_detalle
                            (elemento_id, version_estimacion_id, estimacion_param_complejidad_id, cantidad)
                        values (
                            :ELEMENTO_ID,
                            (select version_estimacion_id from elementos where elemento_id = :ELEMENTO_ID),
                            :ESTIMACION_PARAM_COMPLEJIDAD_ID,
                            nvl(:CANTIDAD, 1)
                        )
                        returning linea_detalle_id into :LINEA_DETALLE_ID;
                    when 'U' then
                        update lineas_detalle set
                            estimacion_param_complejidad_id = :ESTIMACION_PARAM_COMPLEJIDAD_ID,
                            cantidad = :CANTIDAD
                        where linea_detalle_id = :LINEA_DETALLE_ID;
                    when 'D' then
                        delete from lineas_detalle where linea_detalle_id = :LINEA_DETALLE_ID;
                    end case;
                end;
                ```
        }
    )

    region region-resumen (
        name: Resumen
        type: classicReport
        source {
            location: localDatabase
            type: sqlQuery
            sqlQuery:
                ```sql
                with prog as (
                    select nvl(sum(ld.cantidad * epc.horas), 0) h
                    from elementos e
                    join lineas_detalle ld on e.elemento_id = ld.elemento_id
                    join estimacion_parametros_complejidad epc
                        on ld.estimacion_param_complejidad_id = epc.estimacion_param_complejidad_id
                    where e.version_estimacion_id = :P221_VERSION_ESTIMACION_ID
                ),
                params as (
                    select concepto, base_calculo, porcentaje, orden
                    from estimacion_parametros_tiempo_adicional
                    where version_estimacion_id = :P221_VERSION_ESTIMACION_ID
                ),
                horas as (
                    select
                        p.h as h_prog,
                        p.h + sum(case when pa.base_calculo = 'PROGRAMACION'
                                       then p.h * pa.porcentaje / 100 else 0 end) as h_const
                    from prog p, params pa
                    group by p.h
                )
                select ord, concepto, pct, horas from (
                    select 0  ord, 'Programación'          concepto, null               pct, h.h_prog horas from horas h
                    union all
                    select case p.base_calculo when 'PROGRAMACION' then p.orden else 50 + p.orden end,
                           p.concepto, p.porcentaje,
                           case p.base_calculo
                               when 'PROGRAMACION'          then h.h_prog  * p.porcentaje / 100
                               when 'SUBTOTAL_CONSTRUCCION' then h.h_const * p.porcentaje / 100
                           end
                    from params p, horas h
                    union all
                    select 49, 'Subtotal construcción', null, h.h_const from horas h
                    union all
                    select 99, 'TOTAL', null,
                           h.h_const + sum(case p.base_calculo
                                               when 'SUBTOTAL_CONSTRUCCION' then h.h_const * p.porcentaje / 100
                                               else 0 end)
                    from params p, horas h
                    group by h.h_const
                )
                order by ord
                ```
            pageItemsToSubmit: P221_VERSION_ESTIMACION_ID
        }
        layout {
            sequence: 30
            slot: body
        }
        appearance {
            template: @/reports
            templateOptions: #DEFAULT#
        }

        column ORD (
            type: hidden
            heading { heading: Ord }
            layout { sequence: 10 }
            source { dataType: NUMBER }
        )

        column CONCEPTO (
            type: plainText
            heading { heading: Concepto }
            layout { sequence: 20 }
            source { dataType: STRING }
        )

        column PCT (
            type: plainText
            heading { heading: % }
            layout { sequence: 30 }
            appearance { formatMask: FM990.99 }
            source { dataType: NUMBER }
        )

        column HORAS (
            type: plainText
            heading { heading: Horas }
            layout { sequence: 40 }
            appearance { formatMask: FM9990.99 }
            source { dataType: NUMBER }
        )

    )

    dynamicAction actualizar-resumen-por-lineas (
        name: Actualizar resumen al guardar líneas
        execution {
            sequence: 10
        }
        when {
            event: apexafterrefresh
            selectionType: region
            region: @ig-lineas
        }

        action refresh-resumen-lineas (
            action: refresh
            affectedElements {
                selectionType: region
                region: @region-resumen
            }
            execution {
                sequence: 10
                fireOnInit: false
            }
        )

    )

    dynamicAction actualizar-resumen-por-elementos (
        name: Actualizar resumen al guardar elementos
        execution {
            sequence: 20
        }
        when {
            event: apexafterrefresh
            selectionType: region
            region: @ig-elementos
        }

        action refresh-resumen-elementos (
            action: refresh
            affectedElements {
                selectionType: region
                region: @region-resumen
            }
            execution {
                sequence: 10
                fireOnInit: false
            }
        )

    )
```

- [ ] **Step 2: Importar y verificar master-detail**

Importar con el mismo comando rsync + apex import de Tasks anteriores.

Verificar en el navegador:
1. En p221, el IG Elementos muestra los elementos de la versión
2. Al hacer clic en una fila del IG Elementos, el IG Líneas se filtra mostrando solo las líneas de ese elemento
3. Agregar una línea: elegir tipo/nivel en el select list, ingresar cantidad, guardar → fila persiste con el cálculo de horas visible
4. El Classic Report Resumen muestra valores coherentes con las líneas ingresadas
5. Al guardar líneas, el resumen se refresca automáticamente

Verificar en DB:
```sql
SELECT ld.*, epc.tipo_elemento, epc.nivel_complejidad, epc.horas,
       ld.cantidad * epc.horas as horas_total
FROM estimador.lineas_detalle ld
JOIN estimador.estimacion_parametros_complejidad epc
    ON ld.estimacion_param_complejidad_id = epc.estimacion_param_complejidad_id
WHERE ld.elemento_id = <id_elemento_prueba>
```

- [ ] **Step 3: Exportar, sincronizar y commitear**

```bash
# Export via MCP sqlcl: apex export -applicationid 100 -expType APEXLANG -dir /tmp/apex-export-221
rsync -a --exclude='workspace-components' /tmp/apex-export-221/ \
  /home/jean/projects/estimador-migracion/estimador-migraciones-forms-apex/
git add estimador-migraciones-forms-apex/
git commit -m "feat: p221 detalle versión — IGs master-detail elementos/líneas + resumen calculado"
```

---

## Task 5: Modificar p210 — link a estimaciones por proyecto

**Files:**
- Modify: `estimador-migraciones-forms-apex/pages/p00210-proyectos-cliente.apx`

**Interfaces:**
- Consumes: `#PROYECTO_ID#` y `&P210_CLIENTE_ID.` de la fila del IR
- Produces: navegación a p220 con `P220_PROYECTO_ID` y `P220_CLIENTE_ID` seteados

> **Nota de implementación:** p210 ya usa `linkColumn: customTarget` para el ícono de editar (fa-edit → p211). APEX IR permite un solo `customTarget`. Para el segundo ícono (fa-calculator → p220), la opción más segura es agregarlo **desde el APEX Builder** (agregar una columna de tipo "Link" en el IR) y luego exportar el resultado. Esto evita construir URLs manualmente y garantiza que APEX genere el checksum correcto para `P220_PROYECTO_ID`.

- [ ] **Step 1: Agregar la columna de link en el APEX Builder**

1. Abrir la app 100 en el Builder → Página 210 → IR `ir-proyectos`
2. En Columns, agregar nueva columna:
   - **Type:** Link
   - **Heading:** Estimaciones
   - **Link:** Page 220, set items `P220_PROYECTO_ID = #PROYECTO_ID#`, `P220_CLIENTE_ID = #P210_CLIENTE_ID#`, clear cache: 220
   - **Link Icon:** `<span class="fa fa-calculator" title="Estimaciones"></span>`
3. Guardar y verificar en el navegador que el ícono aparece en cada fila del IR y navega correctamente a p220

- [ ] **Step 2: Exportar y sincronizar**

```bash
# Export via MCP sqlcl: apex export -applicationid 100 -expType APEXLANG -dir /tmp/apex-export-p210
rsync -a --exclude='workspace-components' /tmp/apex-export-p210/ \
  /home/jean/projects/estimador-migracion/estimador-migraciones-forms-apex/
```

- [ ] **Step 3: Commit**

```bash
git add estimador-migraciones-forms-apex/pages/p00210-proyectos-cliente.apx
git commit -m "feat: p210 — ícono fa-calculator para acceder a estimaciones de cada proyecto"
```

---

## Task 6: Verificación del flujo completo

- [ ] **Step 1: Recorrer el camino feliz completo**

1. p200 → seleccionar un cliente → p210 (lista de proyectos)
2. Hacer clic en fa-calculator de un proyecto → p220 (lista de versiones, vacía)
3. "Nueva versión" → crear versión → redirect a p221
4. En p221, agregar 2-3 elementos
5. Seleccionar cada elemento y agregar líneas (distintos tipos/niveles/cantidades)
6. Verificar que el resumen muestra horas correctas y se actualiza al guardar
7. Volver a p220 → verificar que la versión aparece en el IR
8. Crear una segunda versión → verificar que tiene `numero_version = 2` y su propio snapshot independiente

- [ ] **Step 2: Verificar snapshot independiente**

```sql
-- Cambiar un parámetro global
UPDATE estimador.parametros_complejidad
SET horas = 99
WHERE tipo_elemento = 'FORMULARIO' AND nivel_complejidad = 'SIMPLE';

-- Verificar que versiones ya creadas no cambiaron
SELECT epc.version_estimacion_id, epc.tipo_elemento, epc.nivel_complejidad, epc.horas
FROM estimador.estimacion_parametros_complejidad epc
JOIN estimador.versiones_estimacion v ON epc.version_estimacion_id = v.version_estimacion_id
WHERE epc.tipo_elemento = 'FORMULARIO' AND epc.nivel_complejidad = 'SIMPLE'
ORDER BY v.numero_version;

-- Revertir el cambio
UPDATE estimador.parametros_complejidad
SET horas = 3
WHERE tipo_elemento = 'FORMULARIO' AND nivel_complejidad = 'SIMPLE';
COMMIT;
```

Las versiones ya creadas deben mostrar `horas = 3`, no 99.

- [ ] **Step 3: Estado final del repo**

```bash
git status  # debe estar limpio
git log --oneline -5
```
