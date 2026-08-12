# Admin Parámetros — Auditoría UPDATED_BY/UPDATED_AT

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Poblar automáticamente `UPDATED_BY` y `UPDATED_AT` en las tres tablas de parámetros al guardar cambios desde la página p00100.

**Architecture:** Tres triggers `BEFORE UPDATE` en el schema `ESTIMADOR`. El DML automático del IG de APEX dispara el trigger; `sys_context('APEX$SESSION','APP_USER')` devuelve el usuario autenticado de la sesión APEX. Sin cambios en la capa APEX.

**Tech Stack:** Oracle Database 23c, PL/SQL, SQLcl MCP (`estimador_freepdb1`), Oracle APEX 26.

## Global Constraints

- Schema: `ESTIMADOR`, base de datos local `FREEPDB1`.
- Conexión SQLcl: `estimador_freepdb1` (MCP, ya configurada — no pedir credenciales).
- Los migrations van en `db/migrations/` con nombre `NNN_descripcion.sql`.
- El siguiente número de migration disponible es `007`.
- No modificar la página APEXlang `p00100` — la página ya está en su estado final.

---

### Task 1: Migration 007 — Triggers de auditoría

**Files:**
- Create: `db/migrations/007_audit_triggers_parametros.sql`

- [ ] **Step 1: Verificar el último migration aplicado**

Confirmar en la BD que las tablas objetivo existen y que `UPDATED_BY`/`UPDATED_AT` están vacíos:

```sql
select 'PARAMETROS_COMPLEJIDAD' as tabla, count(*) as filas,
       count(updated_by) as con_updated_by
from estimador.parametros_complejidad
union all
select 'PARAMETROS_TIEMPO_ADICIONAL', count(*), count(updated_by)
from estimador.parametros_tiempo_adicional
union all
select 'PARAMETROS_ETAPA_CASE', count(*), count(updated_by)
from estimador.parametros_etapa_case;
```

Resultado esperado: filas > 0, `con_updated_by = 0` en las tres tablas.

- [ ] **Step 2: Crear el archivo de migration**

Crear `db/migrations/007_audit_triggers_parametros.sql` con este contenido exacto:

```sql
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
```

- [ ] **Step 3: Ejecutar el migration contra la BD**

Via SQLcl MCP (`estimador_freepdb1`), ejecutar el contenido del archivo. Verificar que los tres triggers se crean sin errores:

```sql
select trigger_name, status
from all_triggers
where owner = 'ESTIMADOR'
  and trigger_name in (
    'TRG_PARAMETROS_COMPLEJIDAD_BU',
    'TRG_PARAMETROS_TIEMPO_ADICIONAL_BU',
    'TRG_PARAMETROS_ETAPA_CASE_BU'
  )
order by trigger_name;
```

Resultado esperado: 3 filas, `STATUS = 'ENABLED'`.

- [ ] **Step 4: Verificar el trigger con un UPDATE directo**

Hacer un UPDATE de prueba en una fila y confirmar que los campos se populan:

```sql
update estimador.parametros_complejidad
set horas = horas
where rownum = 1;
commit;

select parametro_complejidad_id, horas, updated_by, updated_at
from estimador.parametros_complejidad
where updated_by is not null;
```

Resultado esperado: al menos 1 fila con `UPDATED_BY` = usuario de la conexión SQLcl y `UPDATED_AT` = timestamp reciente.

> Nota: desde SQLcl el usuario no es un usuario APEX, por lo que `APP_USER` puede quedar null o mostrar el usuario de BD. La verificación real con usuario APEX se hace en Step 5.

- [ ] **Step 5: Verificar desde la app APEX**

1. Navegar a la app APEX → menú "Parámetros" → página 100.
2. Editar cualquier valor de horas en el IG de complejidad.
3. Hacer clic en Save.
4. Confirmar que las columnas "Último cambio por" y "Fecha" se actualizan con el usuario logueado y el timestamp.

- [ ] **Step 6: Commit**

```bash
git add db/migrations/007_audit_triggers_parametros.sql
git commit -m "feat: triggers auditoría UPDATED_BY/UPDATED_AT en tablas de parámetros"
```
