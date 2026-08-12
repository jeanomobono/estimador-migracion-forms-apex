# Administración de Parámetros — Spec

**Fecha:** 2026-08-11
**Módulo:** Administración de Parámetros (página `p00100`)
**Estado:** Aprobado

---

## Contexto

La página `p00100` existe y tiene tres Interactive Grids en modo update-only:

| IG | Tabla | Campos editables |
|----|-------|-----------------|
| `ig-complejidad` | `PARAMETROS_COMPLEJIDAD` | `HORAS` |
| `ig-tiempo-adicional` | `PARAMETROS_TIEMPO_ADICIONAL` | `PORCENTAJE` |
| `ig-etapa-case` | `PARAMETROS_ETAPA_CASE` | `PESO_PORCENTAJE`, `RECURSOS_PARALELOS` |

Los tres usan `interactiveGridAutoRowProcessing` (DML automático contra tabla). Los datos iniciales del Excel ya están cargados. La navegación ya incluye "Parámetros → p100".

Los campos `UPDATED_BY` y `UPDATED_AT` existen en las tres tablas pero quedan vacíos porque el DML automático no los popula.

---

## Objetivo

Que al guardar cambios en cualquier IG de parámetros queden registrados el usuario y el timestamp de la modificación en `UPDATED_BY` y `UPDATED_AT`.

---

## Diseño

### BD — Migration 007

Tres triggers `BEFORE UPDATE`, uno por tabla:

```sql
CREATE OR REPLACE TRIGGER estimador.trg_parametros_complejidad_bu
BEFORE UPDATE ON estimador.parametros_complejidad
FOR EACH ROW
BEGIN
    :new.updated_by := sys_context('APEX$SESSION', 'APP_USER');
    :new.updated_at := systimestamp;
END;

CREATE OR REPLACE TRIGGER estimador.trg_parametros_tiempo_adicional_bu
BEFORE UPDATE ON estimador.parametros_tiempo_adicional
FOR EACH ROW
BEGIN
    :new.updated_by := sys_context('APEX$SESSION', 'APP_USER');
    :new.updated_at := systimestamp;
END;

CREATE OR REPLACE TRIGGER estimador.trg_parametros_etapa_case_bu
BEFORE UPDATE ON estimador.parametros_etapa_case
FOR EACH ROW
BEGIN
    :new.updated_by := sys_context('APEX$SESSION', 'APP_USER');
    :new.updated_at := systimestamp;
END;
```

`sys_context('APEX$SESSION', 'APP_USER')` devuelve el usuario autenticado de la sesión APEX, disponible en el contexto de trigger porque APEX setea ese contexto antes de ejecutar DML.

### APEX — p00100

Sin cambios. La página ya está en su estado final.

---

## Lo que NO está en scope

- Agregar o eliminar filas de parámetros (los valores son fijos, solo se editan).
- Historial de cambios / auditoría completa (solo se guarda el último cambio).
- Validaciones de negocio (ej. que los porcentajes sumen 100%) — fuera de scope por ahora.

---

## Verificación

1. Editar un valor en cualquier IG y hacer Save.
2. Confirmar que `UPDATED_BY` muestra el usuario logueado y `UPDATED_AT` el timestamp de la operación.
