# Módulo de Estimaciones — Diseño

## 1. Navegación y estructura de páginas

### Punto de entrada
`p210` (Proyectos del cliente) agrega un segundo ícono por fila en el IR, a la derecha del `fa-edit` existente:
- `fa-calculator` → `p220`, pasando `P220_PROYECTO_ID = #PROYECTO_ID#` y `P220_CLIENTE_ID = #P210_CLIENTE_ID#`

### Jerarquía de páginas
```
p200 Lista clientes
  └─ p210 Proyectos del cliente
        └─ p220 Versiones de estimación (nuevo)
              └─ p221 Detalle de versión    (nuevo)
```

### Parámetros de sesión
| Página | Item | Descripción |
|--------|------|-------------|
| p220 | `P220_PROYECTO_ID` | FK a PROYECTOS |
| p220 | `P220_CLIENTE_ID` | Para breadcrumb y botón Editar |
| p221 | `P221_VERSION_ESTIMACION_ID` | FK a VERSIONES_ESTIMACION |
| p221 | `P221_PROYECTO_ID` | Para breadcrumb y navegación de regreso |

Ambos items de sesión usan `checksumRequiredSessionLevel` para protección.

---

## 2. Página p220 — Lista de versiones

### IR `ir-versiones`
```sql
SELECT v.version_estimacion_id,
       v.numero_version,
       v.created_by,
       v.created_at
FROM versiones_estimacion v
WHERE v.proyecto_id = :P220_PROYECTO_ID
ORDER BY v.numero_version
```
`pageItemsToSubmit: P220_PROYECTO_ID`

Columnas visibles: **Versión** (NUMERO_VERSION), **Creado por**, **Fecha creación** (DD/MM/YYYY HH24:MI).

`linkColumn: customTarget` con ícono `fa-table-rows` → p221, pasando `P221_VERSION_ESTIMACION_ID = #VERSION_ESTIMACION_ID#` y `P221_PROYECTO_ID = #P220_PROYECTO_ID#`.

Mensaje sin datos: `"No hay versiones para este proyecto. Haga clic en «Nueva versión» para crear la primera."`

### Botones (slot `rightOfInteractiveReportSearchBar`)
| Botón | Ícono | Acción |
|-------|-------|--------|
| Volver al proyecto | fa-arrow-left | Redirect → p211, `P211_PROYECTO_ID = &P220_PROYECTO_ID.` |
| Nueva versión | fa-plus (hot) | Submit → proceso PL/SQL en p220 |

### Proceso `crear-version`
`type: executeCode`, corre al submit del botón "Nueva versión":

```plsql
DECLARE
  l_version_id NUMBER;
  l_num        NUMBER;
BEGIN
  SELECT NVL(MAX(numero_version), 0) + 1
  INTO l_num
  FROM versiones_estimacion
  WHERE proyecto_id = :P220_PROYECTO_ID;

  INSERT INTO versiones_estimacion (proyecto_id, numero_version, created_by, created_at)
  VALUES (:P220_PROYECTO_ID, l_num, :APP_USER, SYSTIMESTAMP)
  RETURNING version_estimacion_id INTO l_version_id;

  -- Snapshot parámetros de complejidad
  INSERT INTO estimacion_parametros_complejidad
    (version_estimacion_id, tipo_elemento, nivel_complejidad, horas)
  SELECT l_version_id, tipo_elemento, nivel_complejidad, horas
  FROM parametros_complejidad;

  -- Snapshot parámetros de tiempo adicional
  INSERT INTO estimacion_parametros_tiempo_adicional
    (version_estimacion_id, concepto, base_calculo, porcentaje, orden)
  SELECT l_version_id, concepto, base_calculo, porcentaje, orden
  FROM parametros_tiempo_adicional;

  -- Snapshot parámetros de etapa CASE
  INSERT INTO estimacion_parametros_etapa_case
    (version_estimacion_id, etapa, orden, peso_porcentaje, recursos_paralelos)
  SELECT l_version_id, etapa, orden, peso_porcentaje, recursos_paralelos
  FROM parametros_etapa_case;

  :P221_VERSION_ESTIMACION_ID := l_version_id;
  :P221_PROYECTO_ID            := :P220_PROYECTO_ID;
END;
```

Después del proceso: redirect a p221 (`clearCache: 221`).

### Dynamic action `refresh-after-modal`
Evento `apexafterclosedialog` sobre `ir-versiones` → acción `refresh` sobre `ir-versiones`. (Mismo patrón que p210.)

---

## 3. Página p221 — Detalle de versión

Breadcrumb: Clientes > Proyectos > Estimaciones > Versión N

Layout en `body`:
1. IG Elementos (master) — seq 10
2. IG Líneas (detail) — seq 20
3. Resumen calculado — seq 30

### 3a. IG Elementos — `ig-elementos`

```sql
SELECT elemento_id, version_estimacion_id, nombre
FROM elementos
WHERE version_estimacion_id = :P221_VERSION_ESTIMACION_ID
ORDER BY elemento_id
```
`pageItemsToSubmit: P221_VERSION_ESTIMACION_ID`

```apexlang
advanced { htmlDomId: ig_elementos }   -- DOM id para CSS; el masterDetail del detail usa el static id de la región: @ig-elementos
```

Columnas editables: **Nombre del elemento** (`NOMBRE`, text field).  
`ELEMENTO_ID` y `VERSION_ESTIMACION_ID`: hidden.

DML — `targetType: plsqlCode`:
```plsql
CASE :APEX$ROW_STATUS
WHEN 'C' THEN
  INSERT INTO elementos (version_estimacion_id, nombre)
  VALUES (:P221_VERSION_ESTIMACION_ID, :NOMBRE)
  RETURNING elemento_id INTO :ELEMENTO_ID;
WHEN 'U' THEN
  UPDATE elementos SET nombre = :NOMBRE
  WHERE elemento_id = :ELEMENTO_ID;
WHEN 'D' THEN
  DELETE FROM elementos WHERE elemento_id = :ELEMENTO_ID;
END CASE;
```

### 3b. IG Líneas — `ig-lineas` (native master-detail)

```sql
SELECT ld.linea_detalle_id,
       ld.elemento_id,
       ld.estimacion_param_complejidad_id,
       ld.cantidad,
       ld.cantidad * epc.horas AS horas_total
FROM lineas_detalle ld
JOIN estimacion_parametros_complejidad epc
    ON ld.estimacion_param_complejidad_id = epc.estimacion_param_complejidad_id
```
**Sin WHERE** — APEX filtra automáticamente por el row seleccionado en el master.

Configuración APEXlang:
```apexlang
masterDetail {
    masterRegion: @ig-elementos
}
```

Columnas:
| Columna | Tipo | Detalle |
|---------|------|---------|
| `LINEA_DETALLE_ID` | hidden | PK |
| `ELEMENTO_ID` | hidden | FK master; `masterDetail { masterColumn: @ELEMENTO_ID }` |
| `ESTIMACION_PARAM_COMPLEJIDAD_ID` | selectList | LOV inline (ver abajo) |
| `CANTIDAD` | numberField | default `1`; entero positivo |
| `HORAS_TOTAL` | plainText | display only; no DML |

**LOV de `ESTIMACION_PARAM_COMPLEJIDAD_ID`** — inline en la columna:
```sql
SELECT tipo_elemento || ' – ' || NVL(nivel_complejidad, '—') || '  (' || horas || ' h)' display_val,
       estimacion_param_complejidad_id return_val
FROM estimacion_parametros_complejidad
WHERE version_estimacion_id = :P221_VERSION_ESTIMACION_ID
ORDER BY tipo_elemento, horas
```

DML — `targetType: plsqlCode`:
```plsql
CASE :APEX$ROW_STATUS
WHEN 'C' THEN
  INSERT INTO lineas_detalle (elemento_id, version_estimacion_id, estimacion_param_complejidad_id, cantidad)
  VALUES (:ELEMENTO_ID,
          (SELECT version_estimacion_id FROM elementos WHERE elemento_id = :ELEMENTO_ID),
          :ESTIMACION_PARAM_COMPLEJIDAD_ID,
          NVL(:CANTIDAD, 1))
  RETURNING linea_detalle_id INTO :LINEA_DETALLE_ID;
WHEN 'U' THEN
  UPDATE lineas_detalle
  SET estimacion_param_complejidad_id = :ESTIMACION_PARAM_COMPLEJIDAD_ID,
      cantidad = :CANTIDAD
  WHERE linea_detalle_id = :LINEA_DETALLE_ID;
WHEN 'D' THEN
  DELETE FROM lineas_detalle WHERE linea_detalle_id = :LINEA_DETALLE_ID;
END CASE;
```

La subquery en el INSERT evita la necesidad de `pageItemsToSubmit` para `VERSION_ESTIMACION_ID`.

### 3c. Resumen calculado — `region-resumen`

Classic Report, read-only, `pageItemsToSubmit: P221_VERSION_ESTIMACION_ID`.

```sql
WITH prog AS (
    SELECT NVL(SUM(ld.cantidad * epc.horas), 0) h
    FROM elementos e
    JOIN lineas_detalle ld ON e.elemento_id = ld.elemento_id
    JOIN estimacion_parametros_complejidad epc
        ON ld.estimacion_param_complejidad_id = epc.estimacion_param_complejidad_id
    WHERE e.version_estimacion_id = :P221_VERSION_ESTIMACION_ID
),
params AS (
    SELECT concepto, base_calculo, porcentaje, orden
    FROM estimacion_parametros_tiempo_adicional
    WHERE version_estimacion_id = :P221_VERSION_ESTIMACION_ID
),
horas AS (
    SELECT
        p.h                                                                          AS h_prog,
        p.h + SUM(CASE WHEN pa.base_calculo = 'PROGRAMACION'
                       THEN p.h * pa.porcentaje / 100 ELSE 0 END)                  AS h_const
    FROM prog p, params pa
    GROUP BY p.h
)
SELECT ord, concepto, pct, horas FROM (
    SELECT 0  ord, 'Programación'          concepto, null                pct, h.h_prog horas FROM horas h
    UNION ALL
    SELECT CASE p.base_calculo WHEN 'PROGRAMACION' THEN p.orden ELSE 50 + p.orden END,
           p.concepto, p.porcentaje,
           CASE p.base_calculo
               WHEN 'PROGRAMACION'          THEN h.h_prog  * p.porcentaje / 100
               WHEN 'SUBTOTAL_CONSTRUCCION' THEN h.h_const * p.porcentaje / 100
           END
    FROM params p, horas h
    UNION ALL
    SELECT 49, 'Subtotal construcción', null, h.h_const FROM horas h
    UNION ALL
    SELECT 99, 'TOTAL', null,
           h.h_const + SUM(CASE p.base_calculo
                               WHEN 'SUBTOTAL_CONSTRUCCION' THEN h.h_const * p.porcentaje / 100
                               ELSE 0 END)
    FROM params p, horas h
    GROUP BY h.h_const
)
ORDER BY ord
```

Columnas del Classic Report:
| Columna | Heading | Formato |
|---------|---------|---------|
| `CONCEPTO` | Concepto | — |
| `PCT` | % | `FM990.99` (NULL si no aplica) |
| `HORAS` | Horas | `FM9990.99` |

**Dynamic action `actualizar-resumen`**: evento `apexafterrefresh`, selector múltiple sobre `ig-elementos` e `ig-lineas` → acción `refresh` sobre `region-resumen`. Esto recalcula el resumen cada vez que se guarda cualquiera de los dos IGs.

---

## 4. Cambios en base de datos

### Migration 008 — Trigger audit en VERSIONES_ESTIMACION

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

No se necesitan columnas nuevas: la tabla ya tiene `UPDATED_BY` y `UPDATED_AT` nullable.

---

## 5. Cambios en p210

Agregar segundo link en el IR `ir-proyectos`:

```apexlang
link {
    linkColumn: iconColumn
    target: {
        page: 220
        items: {
            P220_PROYECTO_ID: #PROYECTO_ID#
            P220_CLIENTE_ID: &P210_CLIENTE_ID.
        }
        clearCache: 220
    }
    linkIcon: <span role="img" aria-label="Estimaciones" class="fa fa-calculator" title="Ver estimaciones"></span>
}
```

> **Nota sobre `linkColumn: iconColumn`**: APEX permite un solo `customTarget` por IR. Si p210 ya usa `customTarget` para el ícono de editar, el segundo link debe declararse como `iconColumn` (columna de link estándar del IR). Verificar en el export del Builder cómo maneja múltiples links; ajustar si hace falta.

---

## 6. Restricciones y patrones que aplican

- Todo IG editable requiere `APEX$ROW_ACTION`, `APEX$ROW_SELECTOR` y `savedReport` con `displayColumn` completo (lección documentada en memory).
- INSERT con IDENTITY/sequence: siempre `RETURNING pk INTO :PK_BIND` para que APEX no elimine la fila del grid tras el save.
- Import al Builder: `rsync --exclude='workspace-components'` + `apex import -id 100`.
- Slot names en minúsculas (`body`, `breadcrumbBar`).
