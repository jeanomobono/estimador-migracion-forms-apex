# Módulo de Gestión de Clientes y Proyectos — Spec

## Objetivo

Permitir crear, editar y eliminar clientes con su información de contacto, y gestionar los proyectos de migración asociados a cada cliente.

## Decisiones de diseño

- **Navegación**: dos páginas de lista separadas (clientes → proyectos del cliente seleccionado).
- **Formulario de cliente**: página dedicada (Page 201) porque combina campos del cliente + Interactive Grid de contactos.
- **Formulario de proyecto**: modal dialog (Page 211, page mode "Modal Dialog") porque solo tiene un campo editable (NOMBRE).
- **Auditoría**: todas las tablas involucradas tienen CREATED_BY/AT + UPDATED_BY/AT, poblados por triggers BEFORE INSERT/UPDATE usando `SYS_CONTEXT('APEX$SESSION','APP_USER')`.
- **Eliminación**: disponible para clientes, contactos y proyectos. La integridad referencial está protegida por FK constraints + función de manejo de errores ya registrada (`PKG_ERROR_HANDLER`).

---

## Sección 1: Cambios al modelo de datos

### Migración 003

**`CLIENTES`** — agregar columnas:

| Columna | Tipo | Nullable | Notas |
|---|---|---|---|
| `DIRECCION` | `VARCHAR2(400)` | Sí | — |
| `CIUDAD` | `VARCHAR2(200)` | Sí | — |
| `PAIS` | `VARCHAR2(100)` | Sí | — |
| `CREATED_BY` | `VARCHAR2(255)` | No | Seteado por trigger BEFORE INSERT |
| `CREATED_AT` | `TIMESTAMP` | No | Default SYSTIMESTAMP, confirmado por trigger |
| `UPDATED_BY` | `VARCHAR2(255)` | Sí | Seteado por trigger BEFORE UPDATE |
| `UPDATED_AT` | `TIMESTAMP` | Sí | Seteado por trigger BEFORE UPDATE |

Trigger `TRG_CLIENTES_BI`: BEFORE INSERT — setea CREATED_BY/AT.
Trigger `TRG_CLIENTES_BU`: BEFORE UPDATE — setea UPDATED_BY/AT.

**`CONTACTOS_CLIENTE`** — tabla nueva:

| Columna | Tipo | Nullable | Notas |
|---|---|---|---|
| `CONTACTO_ID` | `NUMBER` | No | PK, GENERATED ALWAYS AS IDENTITY |
| `CLIENTE_ID` | `NUMBER` | No | FK → CLIENTES.CLIENTE_ID |
| `DESCRIPCION` | `VARCHAR2(200)` | No | Nombre real o rol del contacto |
| `TELEFONO` | `VARCHAR2(50)` | Sí | — |
| `EMAIL` | `VARCHAR2(200)` | Sí | — |
| `ORDEN` | `NUMBER` | No | Default 10, para ordenar |

Constraint FK: `FK_CONTACTOS_CLIENTE` → `PK_CLIENTES`.
Trigger `TRG_CONTACTOS_CLI_BI`: BEFORE INSERT — setea CREATED_BY/AT (si se agregan auditoría; ver nota abajo).

> **Nota**: `CONTACTOS_CLIENTE` no requiere auditoría propia en esta versión — la trazabilidad se captura a nivel del cliente padre.

**`PROYECTOS`** — agregar triggers que faltan:

Trigger `TRG_PROYECTOS_BI`: BEFORE INSERT — setea CREATED_BY = APP_USER, confirma CREATED_AT = SYSTIMESTAMP.
Trigger `TRG_PROYECTOS_BU`: BEFORE UPDATE — setea UPDATED_BY/AT.

(Las columnas CREATED_BY/AT/UPDATED_BY/AT ya existen en la tabla; solo faltan los triggers.)

---

## Sección 2: Estructura de páginas

### Página 200 — Lista de clientes

- **Tipo**: Interactive Report
- **Alias**: `CLIENTES`
- **Slot**: BODY
- **Query**: `SELECT cliente_id, nombre, ciudad, pais FROM clientes ORDER BY nombre`
- **Columna NOMBRE**: link que navega a página 210 pasando `P210_CLIENTE_ID = CLIENTE_ID`
- **Toolbar**: botón "Nuevo cliente" → navega a página 201 sin parámetros
- **Row actions** (Actions Menu por fila):
  - "Editar" → página 201 con `P201_CLIENTE_ID = CLIENTE_ID`
  - "Eliminar" → confirmación + delete via APEX built-in process
- **Breadcrumb**: entrada `clientes` con `pageNumber: 200`

### Página 201 — Formulario de cliente

- **Tipo**: página estándar (no modal)
- **Alias**: `CLIENTE-FORM`
- **Maneja create y edit**: si `P201_CLIENTE_ID` es NULL → insert; si tiene valor → update
- **Region 1 — Form cliente** (type: form, source: CLIENTES):
  - Campos visibles: NOMBRE (requerido), DIRECCION, CIUDAD, PAIS
  - Campo oculto: CLIENTE_ID (PK)
  - Proceso automático de insert/update/delete (Form — Automatic Row Processing)
  - Botón "Guardar":
    - Después de INSERT → redirect a página 201 con el nuevo `P201_CLIENTE_ID` (para que el IG de contactos se habilite)
    - Después de UPDATE → redirect a página 200
  - Botón "Cancelar" → redirect a página 200 sin guardar
  - Botón "Ver proyectos" (solo visible cuando CLIENTE_ID no es NULL) → página 210 con `P210_CLIENTE_ID = P201_CLIENTE_ID`
- **Region 2 — Contactos** (type: Interactive Grid, fuente: CONTACTOS_CLIENTE):
  - Solo visible cuando P201_CLIENTE_ID no es NULL (server-side condition)
  - Query: `SELECT contacto_id, descripcion, telefono, email, orden FROM contactos_cliente WHERE cliente_id = :P201_CLIENTE_ID ORDER BY orden, contacto_id`
  - Edit: enabled, allowedOperations: [insert, update, delete]
  - Columna CLIENTE_ID: hidden, valor predeterminado = `P201_CLIENTE_ID`
  - Proceso: interactiveGridAutoRowProcessing
  - savedReport PRIMARY con displayColumn para cada columna visible
- **Breadcrumb**:
  - Create: `Clientes > Nuevo cliente`
  - Edit: `Clientes > &P201_CLIENTE_NOMBRE.` (item de página oculto poblado en page load)

### Página 210 — Proyectos del cliente

- **Tipo**: Interactive Report
- **Alias**: `PROYECTOS-CLIENTE`
- **Parámetro de entrada**: `P210_CLIENTE_ID` (hidden page item)
- **Query**: `SELECT proyecto_id, nombre, created_by, created_at FROM proyectos WHERE cliente_id = :P210_CLIENTE_ID ORDER BY nombre`
- **Toolbar**: botón "Nuevo proyecto" → abre modal página 211 con `P211_CLIENTE_ID = P210_CLIENTE_ID`
- **Row actions**:
  - "Editar" → abre modal página 211 con `P211_PROYECTO_ID = PROYECTO_ID`
  - "Eliminar" → confirmación + delete
- **Botón "Editar cliente"** (region header o toolbar): navega a página 201 con `P201_CLIENTE_ID = P210_CLIENTE_ID`
- **Breadcrumb**: `Clientes > &P210_CLIENTE_NOMBRE.` (item oculto poblado en page load) > Proyectos

### Página 211 — Modal de proyecto

- **Tipo**: Modal Dialog
- **Alias**: `PROYECTO-MODAL`
- **Parámetros de entrada**: `P211_PROYECTO_ID` (nullable, PK), `P211_CLIENTE_ID`
- **Region**: Form con fuente PROYECTOS
  - Campo visible: NOMBRE (requerido)
  - Campos ocultos: PROYECTO_ID (PK), CLIENTE_ID (valor predeterminado = `P211_CLIENTE_ID`)
  - Proceso automático insert/update
  - Botón "Guardar" → procesa + cierra modal + refresca página 210
  - Botón "Cancelar" → cierra modal

---

## Sección 3: Navegación y breadcrumbs

**Navigation menu** (`lists.apx`): nueva entrada `clientes` con:
- Label: Clientes
- Icon: `fa-building` (o `fa-users`)
- Sequence: 15 (entre Home en 10 y Parámetros en 20)
- Target: página 200

**Breadcrumbs** (`breadcrumbs.apx`): nuevas entradas:
- `clientes`: pageNumber 200, padre del resto
- `nuevo-cliente`: pageNumber 201, parent: `clientes`, visible cuando P201_CLIENTE_ID es NULL
- `editar-cliente`: pageNumber 201, parent: `clientes`, label dinámico via `&P201_CLIENTE_NOMBRE.`
- `proyectos-cliente`: pageNumber 210, parent: `editar-cliente`, label: Proyectos

---

## Restricciones técnicas

- Oracle Database 26 FREE, schema `ESTIMADOR`, conexión MCP `estimador_freepdb1`
- Oracle APEX 26, app ID 100, workspace `APPS`
- Artefactos APEXlang versionados en `estimador-migraciones-forms-apex/`
- Import APEX via workaround: directorio temporal sin `workspace-components/` y sin bloque `genAI` en `application.apx`
- Función de manejo de errores `PKG_ERROR_HANDLER` ya registrada — cubre FK y check constraints
- Convención de páginas: clientes en 200-209, proyectos en 210-219
