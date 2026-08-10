# Módulo de Gestión de Clientes y Proyectos — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir el CRUD completo de clientes (con contactos) y proyectos, con 4 páginas APEX y el DDL de soporte.

**Architecture:** DDL first (migración 003: tabla PAISES, columnas nuevas en CLIENTES y PROYECTOS, tabla CONTACTOS_CLIENTE, triggers); luego 4 páginas APEXlang: IR de clientes (p200), form de cliente con IG de contactos (p201), IR de proyectos del cliente (p210), modal de proyecto (p211).

**Tech Stack:** Oracle PL/SQL, Oracle APEX 26, APEXlang (.apx), sqlcl MCP (`estimador_freepdb1`).

## Global Constraints

- Schema: `ESTIMADOR`, Oracle 26 FREE, instancia `FREEPDB1`
- App APEX id: 100, workspace: `APPS`
- Conexión sqlcl MCP: `estimador_freepdb1`
- Artefactos APEXlang en `estimador-migraciones-forms-apex/` — todo cambio se versiona ahí
- Import APEX: workaround obligatorio — directorio temporal sin `workspace-components/` y sin bloque `genAI` en `application.apx` (ver Task 6)
- `PKG_ERROR_HANDLER` ya registrada — maneja FK y check constraints automáticamente
- Spec completo en `docs/superpowers/specs/2026-08-09-clientes-proyectos-design.md`
- IR columns: usar `type: plainText` (no `textField`); links en IR van dentro de `link { }` a nivel de región (no en columns)
- Form processes: `formInitialization` (point: beforeHeader) + `formAutoRowProcessing`
- Page items de form: usar `source { formRegion: @region-id; column: COL; dataType: ... }`
- Delete en form pages: usar `button delete (behavior { databaseAction: delete; requiresConfirmation: true })`

---

### Task 1: DDL — Migración 003

**Files:**
- Create: `db/migrations/003_clientes_proyectos.sql`

**Interfaces:**
- Produces: tablas PAISES, CONTACTOS_CLIENTE; columnas nuevas en CLIENTES (DIRECCION, CIUDAD, PAIS_ID, CREATED_BY, CREATED_AT, UPDATED_BY, UPDATED_AT) y PROYECTOS (FECHA_INICIO_ESTIMADA, DESCRIPCION); triggers de auditoría para CLIENTES y PROYECTOS

- [ ] **Step 1: Crear el archivo de migración**

Crear `db/migrations/003_clientes_proyectos.sql` con el siguiente contenido exacto:

```sql
-- Migración 003: tabla PAISES, enriquecimiento de CLIENTES y PROYECTOS,
-- tabla CONTACTOS_CLIENTE, y triggers de auditoría
-- Ejecutar como usuario ESTIMADOR contra FREEPDB1

-- 1. Tabla PAISES (debe crearse antes de FK en CLIENTES)
CREATE TABLE PAISES (
    PAIS_ID     NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    NOMBRE      VARCHAR2(100) NOT NULL,
    CODIGO_ISO  CHAR(2),
    ACTIVO      CHAR(1)       DEFAULT 'S' NOT NULL,
    CONSTRAINT CK_PAISES_ACTIVO CHECK (ACTIVO IN ('S','N')),
    CONSTRAINT UQ_PAISES_NOMBRE UNIQUE (NOMBRE)
);

-- Carga inicial de países
INSERT INTO PAISES (NOMBRE, CODIGO_ISO) VALUES ('Argentina', 'AR');
INSERT INTO PAISES (NOMBRE, CODIGO_ISO) VALUES ('Bolivia',   'BO');
INSERT INTO PAISES (NOMBRE, CODIGO_ISO) VALUES ('Brasil',    'BR');
INSERT INTO PAISES (NOMBRE, CODIGO_ISO) VALUES ('Chile',     'CL');
INSERT INTO PAISES (NOMBRE, CODIGO_ISO) VALUES ('Colombia',  'CO');
INSERT INTO PAISES (NOMBRE, CODIGO_ISO) VALUES ('España',    'ES');
INSERT INTO PAISES (NOMBRE, CODIGO_ISO) VALUES ('México',    'MX');
INSERT INTO PAISES (NOMBRE, CODIGO_ISO) VALUES ('Paraguay',  'PY');
INSERT INTO PAISES (NOMBRE, CODIGO_ISO) VALUES ('Perú',      'PE');
INSERT INTO PAISES (NOMBRE, CODIGO_ISO) VALUES ('Uruguay',   'UY');
COMMIT;

-- 2. Enriquecer CLIENTES
ALTER TABLE CLIENTES ADD (
    DIRECCION  VARCHAR2(400),
    CIUDAD     VARCHAR2(200),
    PAIS_ID    NUMBER         CONSTRAINT FK_CLIENTES_PAIS REFERENCES PAISES(PAIS_ID),
    CREATED_BY VARCHAR2(255),
    CREATED_AT TIMESTAMP      DEFAULT SYSTIMESTAMP,
    UPDATED_BY VARCHAR2(255),
    UPDATED_AT TIMESTAMP
);

-- 3. Tabla CONTACTOS_CLIENTE
CREATE TABLE CONTACTOS_CLIENTE (
    CONTACTO_ID NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    CLIENTE_ID  NUMBER        NOT NULL CONSTRAINT FK_CONTACTOS_CLIENTE REFERENCES CLIENTES(CLIENTE_ID),
    DESCRIPCION VARCHAR2(200) NOT NULL,
    TELEFONO    VARCHAR2(50),
    EMAIL       VARCHAR2(200),
    ORDEN       NUMBER        DEFAULT 10 NOT NULL
);

CREATE INDEX IDX_CONTACTOS_CLIENTE ON CONTACTOS_CLIENTE(CLIENTE_ID);

-- 4. Enriquecer PROYECTOS (columnas nuevas; triggers van abajo)
ALTER TABLE PROYECTOS ADD (
    FECHA_INICIO_ESTIMADA DATE,
    DESCRIPCION           VARCHAR2(4000)
);

-- 5. Triggers para CLIENTES
CREATE OR REPLACE TRIGGER TRG_CLIENTES_BI
BEFORE INSERT ON CLIENTES FOR EACH ROW
BEGIN
    :NEW.CREATED_BY := SYS_CONTEXT('APEX$SESSION','APP_USER');
    :NEW.CREATED_AT := SYSTIMESTAMP;
END;
/

CREATE OR REPLACE TRIGGER TRG_CLIENTES_BU
BEFORE UPDATE ON CLIENTES FOR EACH ROW
BEGIN
    :NEW.UPDATED_BY := SYS_CONTEXT('APEX$SESSION','APP_USER');
    :NEW.UPDATED_AT := SYSTIMESTAMP;
END;
/

-- 6. Triggers para PROYECTOS (las columnas CREATED_BY/AT ya existen)
CREATE OR REPLACE TRIGGER TRG_PROYECTOS_BI
BEFORE INSERT ON PROYECTOS FOR EACH ROW
BEGIN
    :NEW.CREATED_BY := SYS_CONTEXT('APEX$SESSION','APP_USER');
    :NEW.CREATED_AT := SYSTIMESTAMP;
END;
/

CREATE OR REPLACE TRIGGER TRG_PROYECTOS_BU
BEFORE UPDATE ON PROYECTOS FOR EACH ROW
BEGIN
    :NEW.UPDATED_BY := SYS_CONTEXT('APEX$SESSION','APP_USER');
    :NEW.UPDATED_AT := SYSTIMESTAMP;
END;
/
```

- [ ] **Step 2: Ejecutar la migración via sqlcl MCP**

Usar `mcp__sqlcl__sql_run` para ejecutar el contenido completo. Dado que el script tiene bloques PL/SQL con `/`, dividir la ejecución en partes: primero el DDL + INSERT + COMMIT (hasta `ALTER TABLE PROYECTOS`), luego cada trigger por separado.

- [ ] **Step 3: Verificar**

```sql
SELECT table_name, status FROM user_objects
WHERE object_name IN ('PAISES','CONTACTOS_CLIENTE',
                      'TRG_CLIENTES_BI','TRG_CLIENTES_BU',
                      'TRG_PROYECTOS_BI','TRG_PROYECTOS_BU')
ORDER BY object_type, object_name
```

Resultado esperado: todas las tablas y triggers con STATUS = VALID.

```sql
SELECT COUNT(*) FROM paises
```

Resultado esperado: 10.

```sql
SELECT column_name FROM user_tab_columns
WHERE table_name = 'CLIENTES' ORDER BY column_id
```

Resultado esperado: incluye DIRECCION, CIUDAD, PAIS_ID, CREATED_BY, CREATED_AT, UPDATED_BY, UPDATED_AT.

- [ ] **Step 4: Commit**

```bash
git add db/migrations/003_clientes_proyectos.sql
git commit -m "Agregar migración 003: PAISES, CONTACTOS_CLIENTE, enriquecimiento de CLIENTES y PROYECTOS"
```

---

### Task 2: APEXlang — Página 200 (Lista de clientes)

**Files:**
- Create: `estimador-migraciones-forms-apex/pages/p00200-clientes.apx`

**Interfaces:**
- Consumes: tablas CLIENTES, PAISES (de Task 1)
- Produces: página 200 `CLIENTES` — punto de entrada al módulo; el link de edición apunta a p201; el botón Nuevo también

- [ ] **Step 1: Crear `p00200-clientes.apx`**

```apexlang
page 200 (
    name: Clientes
    alias: CLIENTES
    title: Clientes
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

    region breadcrumb-clientes (
        name: Clientes
        type: breadcrumb
        source {
            breadcrumb: @breadcrumb
        }
        layout {
            sequence: 10
            slot: REGION_POSITION_01
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

    region ir-clientes (
        name: Clientes
        type: interactiveReport
        source {
            location: localDatabase
            type: sqlQuery
            sqlQuery:
                ```sql
                select
                    c.cliente_id,
                    c.nombre,
                    c.ciudad,
                    p.nombre as pais
                from clientes c
                left join paises p on p.pais_id = c.pais_id
                order by c.nombre
                ```
        }
        layout {
            sequence: 20
            slot: BODY
        }
        appearance {
            template: @/interactive-report
            templateOptions: #DEFAULT#
        }
        link {
            linkColumn: customTarget
            target: {
                page: 201
                items: {
                    P201_CLIENTE_ID: #CLIENTE_ID#
                }
                clearCache: 201
            }
            linkIcon: <span role="img" aria-label="Editar" class="fa fa-edit" title="Editar cliente"></span>
        }
        messages {
            whenNoDataFound: No hay clientes registrados. Haga clic en "Nuevo cliente" para agregar el primero.
        }

        column CLIENTE_ID (
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
        )

        column NOMBRE (
            type: plainText
            heading {
                heading: Cliente
            }
            layout {
                sequence: 20
            }
            source {
                dataType: STRING
            }
        )

        column CIUDAD (
            type: plainText
            heading {
                heading: Ciudad
            }
            layout {
                sequence: 30
            }
            source {
                dataType: STRING
            }
        )

        column PAIS (
            type: plainText
            heading {
                heading: País
            }
            layout {
                sequence: 40
            }
            source {
                dataType: STRING
            }
        )

        savedReport PRIMARY (
            visibility: primary
            view {
                rowsPerPage: 15
            }
        )
    )

    button nuevo-cliente (
        buttonName: NUEVO_CLIENTE
        label: Nuevo cliente
        layout {
            sequence: 10
            region: @ir-clientes
            slot: RIGHT_OF_IR_SEARCH_BAR
        }
        appearance {
            buttonTemplate: @/text-with-icon
            templateOptions: [
                #DEFAULT#
                t-Button--iconLeft
            ]
            icon: fa-plus
            hot: true
        }
        behavior {
            action: redirectThisApp
            target: {
                page: 201
                clearCache: 201
            }
            warnOnUnsavedChanges: doNotCheck
        }
    )
)
```

- [ ] **Step 2: Validar con apexctl**

```bash
node .agents/skills/apex/apexlang/tools/apexctl.mjs runtime validate \
  --input estimador-migraciones-forms-apex/pages/p00200-clientes.apx \
  --connection estimador_freepdb1
```

Resultado esperado: sin errores. Si hay errores, corregirlos antes de continuar.

- [ ] **Step 3: Commit**

```bash
git add estimador-migraciones-forms-apex/pages/p00200-clientes.apx
git commit -m "Agregar página 200: lista de clientes (Interactive Report)"
```

---

### Task 3: APEXlang — Página 201 (Form de cliente + contactos)

**Files:**
- Create: `estimador-migraciones-forms-apex/pages/p00201-cliente-form.apx`

**Interfaces:**
- Consumes: tablas CLIENTES, PAISES, CONTACTOS_CLIENTE (de Task 1); página 200 (de Task 2) como destino de redirect
- Produces: página 201 `CLIENTE-FORM` — form create/edit de cliente + IG de contactos; expone `P201_CLIENTE_ID` en session state

**Nota sobre branches:** después de INSERT, se redirige a página 201 con el nuevo P201_CLIENTE_ID (para que el IG de contactos quede habilitado). Después de UPDATE o DELETE, a página 200.

- [ ] **Step 1: Crear `p00201-cliente-form.apx`**

```apexlang
page 201 (
    name: Cliente
    alias: CLIENTE-FORM
    title: Cliente
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

    region breadcrumb-cliente (
        name: Cliente
        type: breadcrumb
        source {
            breadcrumb: @breadcrumb
        }
        layout {
            sequence: 10
            slot: REGION_POSITION_01
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

    region buttons-cliente (
        name: Botones
        type: staticContent
        layout {
            sequence: 20
            slot: REGION_POSITION_02
        }
        appearance {
            template: @/buttons-container
            templateOptions: #DEFAULT#
        }
    )

    region form-cliente (
        name: Datos del cliente
        type: form
        source {
            location: localDatabase
            tableName: CLIENTES
        }
        layout {
            sequence: 30
            slot: BODY
        }
        appearance {
            template: @/standard
            templateOptions: #DEFAULT#
        }
        edit {
            enabled: true
        }
    )

    region ig-contactos (
        name: Contactos
        type: interactiveGrid
        advanced {
            htmlDomId: ig_contactos
        }
        layout {
            sequence: 40
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
                    contacto_id,
                    cliente_id,
                    descripcion,
                    telefono,
                    email,
                    orden
                from contactos_cliente
                where cliente_id = :P201_CLIENTE_ID
                order by orden, contacto_id
                ```
        }
        edit {
            enabled: true
            allowedOperations: [
                insert
                update
                delete
            ]
        }
        messages {
            whenNoDataFound: Sin contactos registrados. Use el botón + para agregar.
        }
        toolbar {
            controls: [
                saveButton
                addRow
            ]
        }
        serverSideCondition {
            type: itemIsNotNull
            item: P201_CLIENTE_ID
        }

        savedReport PRIMARY (
            visibility: primary
            view {
                default: grid
            }

            displayColumn (
                column: @DESCRIPCION
                layout { sequence: 1 }
            )

            displayColumn (
                column: @TELEFONO
                layout { sequence: 2 }
            )

            displayColumn (
                column: @EMAIL
                layout { sequence: 3 }
            )

            displayColumn (
                column: @ORDEN
                layout { sequence: 4 }
            )
        )

        column CONTACTO_ID (
            type: hidden
            layout { sequence: 10 }
            source {
                databaseColumn: CONTACTO_ID
                dataType: number
                primaryKey: true
            }
            exportPrinting {
                includeInExportPrint: false
            }
        )

        column CLIENTE_ID (
            type: hidden
            layout { sequence: 20 }
            source {
                databaseColumn: CLIENTE_ID
                dataType: number
            }
            default {
                type: item
                item: P201_CLIENTE_ID
            }
        )

        column DESCRIPCION (
            type: textField
            heading {
                heading: Descripción / Nombre
            }
            layout { sequence: 30 }
            source {
                databaseColumn: DESCRIPCION
                dataType: varchar2
            }
            validation {
                valueRequired: true
            }
        )

        column TELEFONO (
            type: textField
            heading {
                heading: Teléfono
            }
            layout { sequence: 40 }
            source {
                databaseColumn: TELEFONO
                dataType: varchar2
            }
        )

        column EMAIL (
            type: textField
            heading {
                heading: Email
            }
            layout { sequence: 50 }
            source {
                databaseColumn: EMAIL
                dataType: varchar2
            }
        )

        column ORDEN (
            type: numberField
            heading {
                heading: Orden
                alignment: end
            }
            layout {
                sequence: 60
                columnAlignment: end
            }
            source {
                databaseColumn: ORDEN
                dataType: number
            }
        )
    )

    process ARP_CONTACTOS (
        name: IG Contactos - Guardar datos
        type: interactiveGridAutoRowProcessing
        editableRegion: @ig-contactos
        execution {
            sequence: 20
        }
    )

    pageItem P201_CLIENTE_ID (
        type: hidden
        layout {
            sequence: 10
            region: @form-cliente
            slot: regionBody
        }
        source {
            formRegion: @form-cliente
            column: CLIENTE_ID
            dataType: number
            primaryKey: true
        }
        security {
            sessionStateProtection: checksumRequiredSessionLevel
        }
    )

    pageItem P201_CLIENTE_NOMBRE (
        type: hidden
        layout {
            sequence: 11
            region: @form-cliente
            slot: regionBody
        }
    )

    pageItem P201_NOMBRE (
        type: textField
        label {
            label: Nombre del cliente
            alignment: left
        }
        layout {
            sequence: 20
            region: @form-cliente
            slot: regionBody
            alignment: left
        }
        appearance {
            template: @/required-floating
            templateOptions: #DEFAULT#
            width: 60
        }
        validation {
            valueRequired: true
            maxLength: 200
        }
        source {
            formRegion: @form-cliente
            column: NOMBRE
            dataType: varchar2
        }
    )

    pageItem P201_DIRECCION (
        type: textField
        label {
            label: Dirección
            alignment: left
        }
        layout {
            sequence: 30
            region: @form-cliente
            slot: regionBody
            alignment: left
        }
        appearance {
            template: @/optional-floating
            templateOptions: #DEFAULT#
            width: 60
        }
        validation {
            maxLength: 400
        }
        source {
            formRegion: @form-cliente
            column: DIRECCION
            dataType: varchar2
        }
    )

    pageItem P201_CIUDAD (
        type: textField
        label {
            label: Ciudad
            alignment: left
        }
        layout {
            sequence: 40
            region: @form-cliente
            slot: regionBody
            alignment: left
        }
        appearance {
            template: @/optional-floating
            templateOptions: #DEFAULT#
            width: 40
        }
        validation {
            maxLength: 200
        }
        source {
            formRegion: @form-cliente
            column: CIUDAD
            dataType: varchar2
        }
    )

    pageItem P201_PAIS_ID (
        type: selectList
        label {
            label: País
            alignment: left
        }
        lov {
            type: sqlQuery
            sqlQuery:
                ```sql
                select nombre, pais_id
                from paises
                where activo = 'S'
                order by nombre
                ```
            displayNullValue: true
        }
        layout {
            sequence: 50
            region: @form-cliente
            slot: regionBody
            alignment: left
        }
        appearance {
            template: @/optional-floating
            templateOptions: #DEFAULT#
            height: 1
        }
        source {
            formRegion: @form-cliente
            column: PAIS_ID
            dataType: number
        }
    )

    button cancelar (
        buttonName: CANCELAR
        label: Cancelar
        layout {
            sequence: 10
            region: @buttons-cliente
            slot: CLOSE
        }
        appearance {
            buttonTemplate: @/text
            templateOptions: #DEFAULT#
        }
        behavior {
            action: redirectThisApp
            target: {
                page: 200
            }
            warnOnUnsavedChanges: doNotCheck
        }
    )

    button eliminar (
        buttonName: DELETE
        label: Eliminar
        layout {
            sequence: 20
            region: @buttons-cliente
            slot: DELETE
        }
        appearance {
            buttonTemplate: @/text
            templateOptions: #DEFAULT#
        }
        behavior {
            executeValidations: false
            warnOnUnsavedChanges: doNotCheck
            databaseAction: delete
            requiresConfirmation: true
        }
        confirmation {
            message: ¿Estás seguro de que querés eliminar este cliente? Esta acción no se puede deshacer.
            style: danger
        }
        serverSideCondition {
            type: itemIsNotNull
            item: P201_CLIENTE_ID
        }
    )

    button ver-proyectos (
        buttonName: VER_PROYECTOS
        label: Ver proyectos
        layout {
            sequence: 25
            region: @buttons-cliente
            slot: NEXT
        }
        appearance {
            buttonTemplate: @/text-with-icon
            templateOptions: [
                #DEFAULT#
                t-Button--iconLeft
            ]
            icon: fa-briefcase
        }
        behavior {
            action: redirectThisApp
            target: {
                page: 210
                items: {
                    P210_CLIENTE_ID: &P201_CLIENTE_ID.
                }
            }
            warnOnUnsavedChanges: doNotCheck
        }
        serverSideCondition {
            type: itemIsNotNull
            item: P201_CLIENTE_ID
        }
    )

    button guardar (
        buttonName: APPLY-CHANGES
        label: Guardar
        layout {
            sequence: 30
            region: @buttons-cliente
            slot: NEXT
        }
        appearance {
            buttonTemplate: @/text
            templateOptions: #DEFAULT#
            hot: true
        }
        behavior {
            warnOnUnsavedChanges: doNotCheck
            databaseAction: update
        }
        serverSideCondition {
            type: itemIsNotNull
            item: P201_CLIENTE_ID
        }
    )

    button crear (
        buttonName: CREATE
        label: Crear cliente
        layout {
            sequence: 30
            region: @buttons-cliente
            slot: NEXT
        }
        appearance {
            buttonTemplate: @/text
            templateOptions: #DEFAULT#
            hot: true
        }
        behavior {
            warnOnUnsavedChanges: doNotCheck
            databaseAction: insert
        }
        serverSideCondition {
            type: itemIsNull
            item: P201_CLIENTE_ID
        }
    )

    process INIT_CLIENTE (
        name: Inicializar form cliente
        type: formInitialization
        formRegion: @form-cliente
        execution {
            sequence: 10
            point: beforeHeader
        }
    )

    computation COMPUTE_CLIENTE_NOMBRE (
        itemName: P201_CLIENTE_NOMBRE
        execution {
            sequence: 5
            point: beforeRegions
        }
        computation {
            type: sqlQuerySingleValue
            sqlQuery:
                ```sql
                select case
                           when :P201_CLIENTE_ID is null then 'Nuevo cliente'
                           else (select nombre from clientes where cliente_id = :P201_CLIENTE_ID)
                       end
                from dual
                ```
        }
    )

    process SAVE_CLIENTE (
        name: Guardar cliente
        type: formAutoRowProcessing
        formRegion: @form-cliente
        execution {
            sequence: 10
        }
    )

    branch AFTER_INSERT (
        name: Redirigir a edición tras crear cliente
        behavior {
            type: page
            pageNumber: 201
        }
        execution {
            sequence: 5
            point: afterProcessing
        }
        serverSideCondition {
            type: requestIsEqualToValue
            value: CREATE
        }
    )

    branch AFTER_SAVE_DELETE (
        name: Redirigir a lista de clientes
        behavior {
            type: page
            pageNumber: 200
        }
        execution {
            sequence: 10
            point: afterProcessing
        }
        serverSideCondition {
            type: requestIsContainedInValue
            value: APPLY-CHANGES,DELETE
        }
    )
)
```

- [ ] **Step 2: Validar con apexctl**

```bash
node .agents/skills/apex/apexlang/tools/apexctl.mjs runtime validate \
  --input estimador-migraciones-forms-apex/pages/p00201-cliente-form.apx \
  --connection estimador_freepdb1
```

Resultado esperado: sin errores. Si hay errores de sintaxis (especialmente en `branch`, `computation`, o `default` en IG column), corregirlos según el error del compiler antes de continuar.

- [ ] **Step 3: Commit**

```bash
git add estimador-migraciones-forms-apex/pages/p00201-cliente-form.apx
git commit -m "Agregar página 201: form de cliente con IG de contactos"
```

---

### Task 4: APEXlang — Página 210 (Proyectos del cliente)

**Files:**
- Create: `estimador-migraciones-forms-apex/pages/p00210-proyectos-cliente.apx`

**Interfaces:**
- Consumes: tabla PROYECTOS (de Task 1); `P210_CLIENTE_ID` como parámetro de entrada desde p200 o p201
- Produces: página 210 `PROYECTOS-CLIENTE`; abre modal p211 para create/edit de proyecto; provee `P210_CLIENTE_ID` a p211

- [ ] **Step 1: Crear `p00210-proyectos-cliente.apx`**

```apexlang
page 210 (
    name: Proyectos del cliente
    alias: PROYECTOS-CLIENTE
    title: Proyectos
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

    region breadcrumb-proyectos (
        name: Proyectos
        type: breadcrumb
        source {
            breadcrumb: @breadcrumb
        }
        layout {
            sequence: 10
            slot: REGION_POSITION_01
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

    region ir-proyectos (
        name: Proyectos
        type: interactiveReport
        source {
            location: localDatabase
            type: sqlQuery
            sqlQuery:
                ```sql
                select
                    proyecto_id,
                    nombre,
                    fecha_inicio_estimada,
                    created_by,
                    created_at
                from proyectos
                where cliente_id = :P210_CLIENTE_ID
                order by nombre
                ```
        }
        layout {
            sequence: 20
            slot: BODY
        }
        appearance {
            template: @/interactive-report
            templateOptions: #DEFAULT#
        }
        link {
            linkColumn: customTarget
            target: {
                page: 211
                items: {
                    P211_PROYECTO_ID: #PROYECTO_ID#
                    P211_CLIENTE_ID: #P210_CLIENTE_ID#
                }
                clearCache: 211
            }
            linkIcon: <span role="img" aria-label="Editar" class="fa fa-edit" title="Editar proyecto"></span>
        }
        messages {
            whenNoDataFound: No hay proyectos para este cliente. Haga clic en "Nuevo proyecto" para agregar el primero.
        }

        column PROYECTO_ID (
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
        )

        column NOMBRE (
            type: plainText
            heading {
                heading: Proyecto
            }
            layout {
                sequence: 20
            }
            source {
                dataType: STRING
            }
        )

        column FECHA_INICIO_ESTIMADA (
            type: plainText
            heading {
                heading: Inicio estimado
            }
            layout {
                sequence: 30
            }
            appearance {
                formatMask: DD/MM/YYYY
            }
            source {
                dataType: DATE
            }
        )

        column CREATED_BY (
            type: plainText
            heading {
                heading: Creado por
            }
            layout {
                sequence: 40
            }
            source {
                dataType: STRING
            }
        )

        column CREATED_AT (
            type: plainText
            heading {
                heading: Fecha creación
            }
            layout {
                sequence: 50
            }
            appearance {
                formatMask: DD/MM/YYYY HH24:MI
            }
            source {
                dataType: DATE
            }
        )

        savedReport PRIMARY (
            visibility: primary
            view {
                rowsPerPage: 15
            }
        )
    )

    pageItem P210_CLIENTE_ID (
        type: hidden
        layout {
            sequence: 10
            region: @ir-proyectos
            slot: REGION_POSITION_01
        }
        security {
            sessionStateProtection: checksumRequiredSessionLevel
        }
    )

    pageItem P210_CLIENTE_NOMBRE (
        type: hidden
        layout {
            sequence: 20
            region: @ir-proyectos
            slot: REGION_POSITION_01
        }
    )

    button editar-cliente (
        buttonName: EDITAR_CLIENTE
        label: Editar cliente
        layout {
            sequence: 10
            region: @ir-proyectos
            slot: RIGHT_OF_IR_SEARCH_BAR
        }
        appearance {
            buttonTemplate: @/text-with-icon
            templateOptions: [
                #DEFAULT#
                t-Button--iconLeft
            ]
            icon: fa-edit
        }
        behavior {
            action: redirectThisApp
            target: {
                page: 201
                items: {
                    P201_CLIENTE_ID: &P210_CLIENTE_ID.
                }
                clearCache: 201
            }
            warnOnUnsavedChanges: doNotCheck
        }
    )

    button nuevo-proyecto (
        buttonName: NUEVO_PROYECTO
        label: Nuevo proyecto
        layout {
            sequence: 20
            region: @ir-proyectos
            slot: RIGHT_OF_IR_SEARCH_BAR
        }
        appearance {
            buttonTemplate: @/text-with-icon
            templateOptions: [
                #DEFAULT#
                t-Button--iconLeft
            ]
            icon: fa-plus
            hot: true
        }
        behavior {
            action: redirectThisApp
            target: {
                page: 211
                items: {
                    P211_CLIENTE_ID: &P210_CLIENTE_ID.
                }
                clearCache: 211
            }
            warnOnUnsavedChanges: doNotCheck
        }
    )

    computation COMPUTE_CLIENTE_NOMBRE_210 (
        itemName: P210_CLIENTE_NOMBRE
        execution {
            sequence: 5
            point: beforeRegions
        }
        computation {
            type: sqlQuerySingleValue
            sqlQuery:
                ```sql
                select nombre from clientes where cliente_id = :P210_CLIENTE_ID
                ```
        }
    )

    dynamicAction refresh-after-modal (
        name: Actualizar lista de proyectos
        execution {
            sequence: 10
        }
        when {
            event: apexafterclosedialog
            selectionType: region
            region: @ir-proyectos
        }

        action refresh-ir-proyectos (
            action: refresh
            affectedElements {
                selectionType: region
                region: @ir-proyectos
            }
            execution {
                sequence: 10
                event: @refresh-after-modal
                fireOnInit: false
            }
        )
    )
)
```

- [ ] **Step 2: Validar con apexctl**

```bash
node .agents/skills/apex/apexlang/tools/apexctl.mjs runtime validate \
  --input estimador-migraciones-forms-apex/pages/p00210-proyectos-cliente.apx \
  --connection estimador_freepdb1
```

- [ ] **Step 3: Commit**

```bash
git add estimador-migraciones-forms-apex/pages/p00210-proyectos-cliente.apx
git commit -m "Agregar página 210: proyectos del cliente (Interactive Report)"
```

---

### Task 5: APEXlang — Página 211 (Modal de proyecto)

**Files:**
- Create: `estimador-migraciones-forms-apex/pages/p00211-proyecto-modal.apx`

**Interfaces:**
- Consumes: tabla PROYECTOS (de Task 1); `P211_PROYECTO_ID` (nullable, PK), `P211_CLIENTE_ID` como parámetros de entrada desde p210
- Produces: modal que cierra al guardar y dispara `apexafterclosedialog` en p210, que refresca el IR

- [ ] **Step 1: Crear `p00211-proyecto-modal.apx`**

```apexlang
page 211 (
    name: Proyecto
    alias: PROYECTO-MODAL
    title: Proyecto
    appearance {
        pageMode: modalDialog
        dialogTemplate: @/modal-dialog
        templateOptions: #DEFAULT#
    }
    dialog {
        chained: false
    }
    security {
        pageAccessProtection: argumentsMustHaveChecksum
        formAutoComplete: false
    }

    region buttons-proyecto (
        name: Botones
        type: staticContent
        layout {
            sequence: 10
            slot: REGION_POSITION_03
        }
        appearance {
            template: @/buttons-container
            templateOptions: #DEFAULT#
        }
    )

    region form-proyecto (
        name: Proyecto
        type: form
        source {
            location: localDatabase
            tableName: PROYECTOS
        }
        layout {
            sequence: 20
            slot: contentBody
        }
        appearance {
            template: @/blank-with-attributes
            templateOptions: #DEFAULT#
        }
        edit {
            enabled: true
        }
    )

    pageItem P211_PROYECTO_ID (
        type: hidden
        layout {
            sequence: 10
            region: @form-proyecto
            slot: regionBody
        }
        source {
            formRegion: @form-proyecto
            column: PROYECTO_ID
            dataType: number
            primaryKey: true
        }
        security {
            sessionStateProtection: checksumRequiredSessionLevel
        }
    )

    pageItem P211_CLIENTE_ID (
        type: hidden
        layout {
            sequence: 20
            region: @form-proyecto
            slot: regionBody
        }
        source {
            formRegion: @form-proyecto
            column: CLIENTE_ID
            dataType: number
        }
        security {
            sessionStateProtection: checksumRequiredSessionLevel
        }
    )

    pageItem P211_NOMBRE (
        type: textField
        label {
            label: Nombre del proyecto
            alignment: left
        }
        layout {
            sequence: 30
            region: @form-proyecto
            slot: regionBody
            alignment: left
        }
        appearance {
            template: @/required-floating
            templateOptions: #DEFAULT#
            width: 60
        }
        validation {
            valueRequired: true
            maxLength: 200
        }
        source {
            formRegion: @form-proyecto
            column: NOMBRE
            dataType: varchar2
        }
    )

    pageItem P211_FECHA_INICIO_ESTIMADA (
        type: datePicker
        label {
            label: Inicio estimado
            alignment: left
        }
        layout {
            sequence: 40
            region: @form-proyecto
            slot: regionBody
            alignment: left
        }
        appearance {
            template: @/optional-floating
            templateOptions: #DEFAULT#
            width: 32
        }
        source {
            formRegion: @form-proyecto
            column: FECHA_INICIO_ESTIMADA
            dataType: date
        }
    )

    pageItem P211_DESCRIPCION (
        type: textarea
        label {
            label: Descripción
            alignment: left
        }
        layout {
            sequence: 50
            region: @form-proyecto
            slot: regionBody
            alignment: left
        }
        appearance {
            template: @/optional-floating
            templateOptions: #DEFAULT#
            width: 60
            height: 5
        }
        validation {
            maxLength: 4000
        }
        source {
            formRegion: @form-proyecto
            column: DESCRIPCION
            dataType: varchar2
        }
    )

    button cancelar-modal (
        buttonName: CANCEL
        label: Cancelar
        layout {
            sequence: 10
            region: @buttons-proyecto
            slot: CLOSE
        }
        appearance {
            buttonTemplate: @/text
            templateOptions: #DEFAULT#
        }
        behavior {
            action: definedByDynamicAction
        }
    )

    button eliminar-proyecto (
        buttonName: DELETE
        label: Eliminar
        layout {
            sequence: 20
            region: @buttons-proyecto
            slot: DELETE
        }
        appearance {
            buttonTemplate: @/text
            templateOptions: #DEFAULT#
        }
        behavior {
            executeValidations: false
            warnOnUnsavedChanges: doNotCheck
            databaseAction: delete
            requiresConfirmation: true
        }
        confirmation {
            message: ¿Estás seguro de que querés eliminar este proyecto?
            style: danger
        }
        serverSideCondition {
            type: itemIsNotNull
            item: P211_PROYECTO_ID
        }
    )

    button guardar-proyecto (
        buttonName: APPLY-CHANGES
        label: Guardar
        layout {
            sequence: 30
            region: @buttons-proyecto
            slot: NEXT
        }
        appearance {
            buttonTemplate: @/text
            templateOptions: #DEFAULT#
            hot: true
        }
        behavior {
            warnOnUnsavedChanges: doNotCheck
            databaseAction: update
        }
        serverSideCondition {
            type: itemIsNotNull
            item: P211_PROYECTO_ID
        }
    )

    button crear-proyecto (
        buttonName: CREATE
        label: Crear proyecto
        layout {
            sequence: 30
            region: @buttons-proyecto
            slot: NEXT
        }
        appearance {
            buttonTemplate: @/text
            templateOptions: #DEFAULT#
            hot: true
        }
        behavior {
            warnOnUnsavedChanges: doNotCheck
            databaseAction: insert
        }
        serverSideCondition {
            type: itemIsNull
            item: P211_PROYECTO_ID
        }
    )

    dynamicAction cancel-dialog (
        name: Cancelar diálogo
        execution {
            sequence: 10
        }
        when {
            event: click
            selectionType: button
            button: @cancelar-modal
        }

        action native-cancel (
            action: cancelDialog
            execution {
                sequence: 10
                event: @cancel-dialog
                fireOnInit: false
            }
        )
    )

    process INIT_PROYECTO (
        name: Inicializar form proyecto
        type: formInitialization
        formRegion: @form-proyecto
        execution {
            sequence: 10
            point: beforeHeader
        }
    )

    process SAVE_PROYECTO (
        name: Guardar proyecto
        type: formAutoRowProcessing
        formRegion: @form-proyecto
        execution {
            sequence: 10
        }
    )

    process CLOSE_DIALOG (
        name: Cerrar modal
        type: closeDialog
        execution {
            sequence: 50
        }
        serverSideCondition {
            type: requestIsContainedInValue
            value: CREATE,APPLY-CHANGES,DELETE
        }
    )
)
```

- [ ] **Step 2: Validar con apexctl**

```bash
node .agents/skills/apex/apexlang/tools/apexctl.mjs runtime validate \
  --input estimador-migraciones-forms-apex/pages/p00211-proyecto-modal.apx \
  --connection estimador_freepdb1
```

- [ ] **Step 3: Commit**

```bash
git add estimador-migraciones-forms-apex/pages/p00211-proyecto-modal.apx
git commit -m "Agregar página 211: modal de proyecto"
```

---

### Task 6: Navegación, breadcrumbs e import

**Files:**
- Modify: `estimador-migraciones-forms-apex/shared-components/lists.apx`
- Modify: `estimador-migraciones-forms-apex/shared-components/breadcrumbs.apx`

**Interfaces:**
- Consumes: páginas 200, 201, 210 (de Tasks 2-4)
- Produces: entradas de nav menu y breadcrumb para el módulo; app importada en APEX y verificada

- [ ] **Step 1: Agregar entrada al navigation menu en `lists.apx`**

En `estimador-migraciones-forms-apex/shared-components/lists.apx`, dentro de `list navigation-menu`, agregar entre la entrada `home` (sequence 10) y `parametros` (sequence 20):

```apexlang
    entry clientes (
        label: Clientes
        icon {
            imageIconCssClasses: fa-building
        }
        layout {
            sequence: 15
        }
        link {
            target: {
                page: 200
            }
        }
    )
```

- [ ] **Step 2: Agregar entradas al breadcrumb en `breadcrumbs.apx`**

En `estimador-migraciones-forms-apex/shared-components/breadcrumbs.apx`, dentro de `breadcrumb breadcrumb`, agregar después de la entrada existente `admin-parametros`:

```apexlang
    entry clientes (
        name: Clientes
        pageNumber: 200
        execution {
            sequence: 30
        }
        link {
            target: {
                page: 200
            }
        }
    )

    entry cliente-form (
        name: &P201_CLIENTE_NOMBRE.
        pageNumber: 201
        execution {
            sequence: 40
        }
        link {
            target: {
                page: 201
                items: {
                    P201_CLIENTE_ID: &P201_CLIENTE_ID.
                }
            }
        }
    )

    entry proyectos-cliente (
        name: Proyectos
        pageNumber: 210
        execution {
            sequence: 50
        }
        link {
            target: {
                page: 210
                items: {
                    P210_CLIENTE_ID: &P210_CLIENTE_ID.
                }
            }
        }
    )
```

- [ ] **Step 3: Preparar directorio temporal e importar**

```bash
rm -rf /tmp/apex-import-100
mkdir /tmp/apex-import-100
cp -r estimador-migraciones-forms-apex/page-groups.apx \
      estimador-migraciones-forms-apex/pages \
      estimador-migraciones-forms-apex/shared-components \
      estimador-migraciones-forms-apex/deployments \
      estimador-migraciones-forms-apex/.apex \
      /tmp/apex-import-100/

# Copiar application.apx sin el bloque genAI
python3 -c "
import re
content = open('estimador-migraciones-forms-apex/application.apx').read()
content = re.sub(r'\n    genAI \{[^}]+\}', '', content)
open('/tmp/apex-import-100/application.apx', 'w').write(content)
"
```

Luego ejecutar via `mcp__sqlcl__sqlcl_run` (ASYNCHRONOUS):
```
apex import -input /tmp/apex-import-100
```

Esperar con `mcp__sqlcl__request_status`. Resultado esperado: `Import successful.`

- [ ] **Step 4: Verificar en DB**

```sql
SELECT page_id, page_name, page_alias
FROM apex_application_pages
WHERE application_id = 100 AND page_id IN (200, 201, 210, 211)
ORDER BY page_id
```

Resultado esperado: 4 filas con los nombres y aliases correctos.

```sql
SELECT display_sequence, entry_text
FROM apex_application_list_entries
WHERE application_id = 100 AND list_name = 'Navigation Menu'
ORDER BY display_sequence
```

Resultado esperado: Home (10), Clientes (15), Parámetros (20).

- [ ] **Step 5: Commit**

```bash
git add estimador-migraciones-forms-apex/shared-components/lists.apx \
        estimador-migraciones-forms-apex/shared-components/breadcrumbs.apx
git commit -m "Agregar navegación y breadcrumbs para módulo de clientes y proyectos"
```

- [ ] **Step 6: Verificación manual en browser**

1. Ir a la app APEX (app id 100) → verificar que aparece "Clientes" en el menú lateral.
2. Hacer clic en "Clientes" → página 200 carga con IR vacío y botón "Nuevo cliente".
3. Hacer clic en "Nuevo cliente" → página 201 carga vacía (form sin IG de contactos).
4. Completar nombre → "Crear cliente" → redirige a página 201 con el nuevo cliente → IG de contactos aparece.
5. Agregar un contacto → guardar → verificar en DB.
6. Hacer clic en "Ver proyectos" → página 210 carga con IR vacío del cliente.
7. Hacer clic en "Nuevo proyecto" → modal 211 abre → completar nombre → crear → modal cierra → IR se refresca.
8. Hacer clic en el ícono de edición en el IR de proyectos → modal 211 abre con datos del proyecto.
