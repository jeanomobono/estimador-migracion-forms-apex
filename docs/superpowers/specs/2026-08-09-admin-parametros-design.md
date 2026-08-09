# Diseño: Módulo de Administración de Parámetros

**Fecha:** 2026-08-09
**Estado:** Aprobado

---

## Contexto

La aplicación APEX de estimación de migraciones Forms→APEX usa tres tablas de parámetros
globales (`PARAMETROS_COMPLEJIDAD`, `PARAMETROS_TIEMPO_ADICIONAL`, `PARAMETROS_ETAPA_CASE`)
cuyos valores iniciales se cargaron en la Fase 1. Estos valores son la fuente para el
snapshot que se congela en cada nueva versión de estimación.

Este módulo permite a los usuarios de Filomeni editar esos parámetros globales desde la
aplicación, sin tocar SQL directamente.

---

## Alcance

- Una sola página APEX (página `100`) con tres secciones de Interactive Grid.
- DDL de soporte: columnas de auditoría + triggers `BEFORE UPDATE` en las tres tablas.
- Entrada de navegación en el menú principal.

**Fuera de alcance:**
- Agregar o eliminar tipos de elemento o niveles de complejidad (son fijos para el dominio Forms→APEX).
- Roles diferenciados: todos los usuarios autenticados pueden editar.
- Historial completo de cambios (audit log): se registra solo el último `UPDATED_BY`/`UPDATED_AT` por fila.

---

## DDL requerido

### Columnas de auditoría (ALTER TABLE)

```sql
ALTER TABLE PARAMETROS_COMPLEJIDAD      ADD (UPDATED_BY VARCHAR2(255), UPDATED_AT TIMESTAMP);
ALTER TABLE PARAMETROS_TIEMPO_ADICIONAL ADD (UPDATED_BY VARCHAR2(255), UPDATED_AT TIMESTAMP);
ALTER TABLE PARAMETROS_ETAPA_CASE       ADD (UPDATED_BY VARCHAR2(255), UPDATED_AT TIMESTAMP);
```

### Triggers BEFORE UPDATE

Un trigger por tabla que setea `UPDATED_BY` desde el contexto APEX y `UPDATED_AT` con
`SYSTIMESTAMP`. Usar `SYS_CONTEXT('APEX$SESSION','APP_USER')` — disponible en sesiones APEX.

```sql
-- Ejemplo para PARAMETROS_COMPLEJIDAD (idéntico para las otras dos):
CREATE OR REPLACE TRIGGER TRG_PARAM_COMPLEJIDAD_BU
BEFORE UPDATE ON PARAMETROS_COMPLEJIDAD
FOR EACH ROW
BEGIN
    :NEW.UPDATED_BY := SYS_CONTEXT('APEX$SESSION','APP_USER');
    :NEW.UPDATED_AT := SYSTIMESTAMP;
END;
/
```

Triggers a crear:
- `TRG_PARAM_COMPLEJIDAD_BU` — sobre `PARAMETROS_COMPLEJIDAD`
- `TRG_PARAM_TIEMPO_ADIC_BU` — sobre `PARAMETROS_TIEMPO_ADICIONAL`
- `TRG_PARAM_ETAPA_CASE_BU`  — sobre `PARAMETROS_ETAPA_CASE`

---

## Página APEX 100 — Administración de Parámetros

### Propiedades generales

| Propiedad | Valor |
|---|---|
| Número de página | 100 |
| Nombre | Administración de Parámetros |
| Título | Parámetros del sistema |
| Autenticación | Debe estar autenticado (heredado de la app) |
| Autorización | Sin esquema diferenciado |

### Navegación

Agregar entrada "Parámetros" en la lista de navegación principal existente
(`shared-components/lists.apx`), apuntando a la página 100.

---

## Región 1 — Horas por complejidad

**Fuente:** tabla `PARAMETROS_COMPLEJIDAD`  
**Tipo de región:** Interactive Grid  
**Título de región:** Horas por nivel de complejidad

### Columnas

| Columna DB | Label | Visible | Editable | Tipo | Validación |
|---|---|---|---|---|---|
| TIPO_ELEMENTO | Tipo | Sí | No | Texto | — |
| NIVEL_COMPLEJIDAD | Nivel | Sí | No | Texto | — |
| HORAS | Horas | Sí | Sí | Numérico | > 0 · Mensaje: "Las horas deben ser mayores a cero" |
| UPDATED_BY | Último cambio por | Sí | No | Texto | — |
| UPDATED_AT | Fecha | Sí | No | Fecha/hora | — |
| PARAMETRO_COMPLEJIDAD_ID | — | No | No | — | PK (solo DML) |

**Orden:** `TIPO_ELEMENTO ASC`, `HORAS ASC`  
**Toolbar:** reducida — sin búsqueda ni filtros, solo botón "Guardar cambios"  
**Operaciones permitidas:** solo UPDATE (agregar/eliminar filas deshabilitado)

---

## Región 2 — Tiempos adicionales

**Fuente:** tabla `PARAMETROS_TIEMPO_ADICIONAL`  
**Tipo de región:** Interactive Grid  
**Título de región:** Tiempos adicionales

### Columnas

| Columna DB | Label | Visible | Editable | Tipo | Validación |
|---|---|---|---|---|---|
| CONCEPTO | Concepto | Sí | No | Texto | — |
| BASE_CALCULO | Base de cálculo | Sí | No | Texto | — |
| PORCENTAJE | Porcentaje (%) | Sí | Sí | Numérico | >= 0 · Mensaje: "El porcentaje no puede ser negativo" |
| UPDATED_BY | Último cambio por | Sí | No | Texto | — |
| UPDATED_AT | Fecha | Sí | No | Fecha/hora | — |
| ORDEN | — | No | No | — | Ordenamiento |
| PARAMETRO_TIEMPO_ADICIONAL_ID | — | No | No | — | PK (solo DML) |

**Orden:** `ORDEN ASC`  
**Toolbar:** reducida — solo botón "Guardar cambios"  
**Operaciones permitidas:** solo UPDATE

---

## Región 3 — Distribución CASE

**Fuente:** tabla `PARAMETROS_ETAPA_CASE`  
**Tipo de región:** Interactive Grid  
**Título de región:** Distribución por etapa CASE

### Columnas

| Columna DB | Label | Visible | Editable | Tipo | Validación |
|---|---|---|---|---|---|
| ETAPA | Etapa | Sí | No | Texto | — |
| PESO_PORCENTAJE | Peso (%) | Sí | Sí | Numérico | >= 0 · Mensaje: "El peso no puede ser negativo" |
| RECURSOS_PARALELOS | Recursos paralelos | Sí | Sí | Numérico | > 0 · Mensaje: "Los recursos paralelos deben ser mayores a cero" |
| UPDATED_BY | Último cambio por | Sí | No | Texto | — |
| UPDATED_AT | Fecha | Sí | No | Fecha/hora | — |
| ORDEN | — | No | No | — | Ordenamiento |
| PARAMETRO_ETAPA_CASE_ID | — | No | No | — | PK (solo DML) |

**Orden:** `ORDEN ASC`  
**Toolbar:** reducida — solo botón "Guardar cambios"  
**Operaciones permitidas:** solo UPDATE

---

## Validaciones

Las validaciones se configuran como "Column Validation" en cada columna editable del IG.
El feedback es inmediato (client-side donde sea posible, server-side como fallback).

No se requiere confirmación modal al guardar.

---

## Artefactos a generar

| Artefacto | Ubicación |
|---|---|
| DDL (ALTER TABLE + triggers) | `db/migrations/001_audit_parametros.sql` |
| Página APEX 100 | `estimador-migraciones-forms-apex/pages/p00100-admin-parametros.apx` |
| Navegación actualizada | `estimador-migraciones-forms-apex/shared-components/lists.apx` |
