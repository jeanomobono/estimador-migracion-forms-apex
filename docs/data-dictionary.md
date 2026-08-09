# Diccionario de datos — Estimador de Migraciones

Schema: `ESTIMADOR` · Oracle Database 26 FREE · Creado en Fase 1

---

## Convención de nombres

| Elemento | Regla | Ejemplo |
|---|---|---|
| Tablas | PLURAL_MAYUSCULAS | `CLIENTES` |
| PKs | `PK_<TABLA>` | `PK_CLIENTES` |
| FKs | `FK_<TABLA_HIJA>_<REFERENCIA>` | `FK_PROYECTOS_CLIENTE` |
| UQs | `UQ_<TABLA>_<COLS>` | `UQ_CLIENTES_NOMBRE` |
| CKs | `CK_<TABLA>_<CONCEPTO>` | `CK_PARAM_COMPLEJIDAD_TIPO` |
| Índices | `IX_<TABLA>_<COLS>` | `IX_PROYECTOS_CLIENTE` |
| PKs autonuméricas | `GENERATED ALWAYS AS IDENTITY` | — |
| Auditoría | `CREATED_BY`, `CREATED_AT`, `UPDATED_BY`, `UPDATED_AT` | — |

---

## Jerarquía principal

```
CLIENTES
  └── PROYECTOS
        └── VERSIONES_ESTIMACION
              ├── ELEMENTOS
              │     └── LINEAS_DETALLE ──────────── ESTIMACION_PARAMETROS_COMPLEJIDAD
              ├── ESTIMACION_PARAMETROS_COMPLEJIDAD
              ├── ESTIMACION_PARAMETROS_TIEMPO_ADICIONAL
              └── ESTIMACION_PARAMETROS_ETAPA_CASE
```

Las tres tablas `ESTIMACION_PARAMETROS_*` son snapshots de los parámetros globales al
momento de crear la versión. Una vez creada la versión, sus parámetros son editables
de forma independiente y no se recalculan si cambian los globales.

---

## Tablas de parámetros globales

### PARAMETROS_COMPLEJIDAD

Horas unitarias por tipo de elemento y nivel de complejidad. Valores vigentes usados
como base para nuevas versiones de estimación.

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `PARAMETRO_COMPLEJIDAD_ID` | NUMBER IDENTITY | No | PK |
| `TIPO_ELEMENTO` | VARCHAR2(20) | No | `FORMULARIO`, `REPORTE`, `PLSQL`, `MENU` |
| `NIVEL_COMPLEJIDAD` | VARCHAR2(20) | Sí | `SIMPLE`, `SEMI_COMPLEJO`, `COMPLEJO`, `MUY_COMPLEJO`, `MUY_COMPLEJO_PLUS`. NULL solo para MENU. |
| `HORAS` | NUMBER(6,2) | No | Horas unitarias estimadas. > 0. |

**Valores iniciales:**

| Tipo | Simple | Semi | Complejo | Muy Compl. | Muy Compl.+ |
|---|---|---|---|---|---|
| FORMULARIO | 4 | 12 | 24 | 32 | 80 |
| PLSQL | 4 | 8 | 24 | 32 | 80 |
| REPORTE | 4 | 8 | 24 | 40 | 64 |
| MENU | 4 (sin nivel) | — | — | — | — |

---

### PARAMETROS_TIEMPO_ADICIONAL

Conceptos de tiempo adicional sobre la programación base y sus porcentajes vigentes.

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `PARAMETRO_TIEMPO_ADICIONAL_ID` | NUMBER IDENTITY | No | PK |
| `CONCEPTO` | VARCHAR2(40) | No | `PRUEBA_FUNCIONAL`, `ADMINISTRACION`, `CONTROL_CALIDAD`, `DBA`, `DOCUMENTACION` |
| `BASE_CALCULO` | VARCHAR2(30) | No | `PROGRAMACION` o `SUBTOTAL_CONSTRUCCION` |
| `PORCENTAJE` | NUMBER(5,2) | No | Porcentaje aplicado sobre la base. >= 0. |
| `ORDEN` | NUMBER(2) | No | Orden de presentación. Único. |

**Valores iniciales:**

| Concepto | Base | % |
|---|---|---|
| PRUEBA_FUNCIONAL | PROGRAMACION | 15 |
| ADMINISTRACION | SUBTOTAL_CONSTRUCCION | 5 |
| CONTROL_CALIDAD | SUBTOTAL_CONSTRUCCION | 1 |
| DBA | SUBTOTAL_CONSTRUCCION | 0 |
| DOCUMENTACION | SUBTOTAL_CONSTRUCCION | 5 |

---

### PARAMETROS_ETAPA_CASE

Distribución porcentual del esfuerzo total entre las etapas del ciclo CASE y recursos
paralelos por etapa. Usada para calcular la duración en semanas/meses del proyecto.

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `PARAMETRO_ETAPA_CASE_ID` | NUMBER IDENTITY | No | PK |
| `ETAPA` | VARCHAR2(20) | No | `ESTRATEGIA`, `ANALISIS`, `DISENO`, `CONSTRUCCION`, `TRANSICION` |
| `ORDEN` | NUMBER(2) | No | Orden secuencial de la etapa. Único. |
| `PESO_PORCENTAJE` | NUMBER(5,2) | No | Peso de la etapa sobre el total. >= 0. Suma 100%. |
| `RECURSOS_PARALELOS` | NUMBER(4,2) | No | Recursos trabajando en paralelo en esta etapa. > 0. |

**Valores iniciales:**

| Etapa | Orden | Peso % | Recursos |
|---|---|---|---|
| ESTRATEGIA | 1 | 7 | 1 |
| ANALISIS | 2 | 13 | 2 |
| DISENO | 3 | 19 | 2 |
| CONSTRUCCION | 4 | 38 | 2 |
| TRANSICION | 5 | 23 | 1 |

---

## Tablas principales

### CLIENTES

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `CLIENTE_ID` | NUMBER IDENTITY | No | PK |
| `NOMBRE` | VARCHAR2(200) | No | Nombre del cliente. Único. |

---

### PROYECTOS

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `PROYECTO_ID` | NUMBER IDENTITY | No | PK |
| `CLIENTE_ID` | NUMBER | No | FK → CLIENTES |
| `NOMBRE` | VARCHAR2(200) | No | Nombre del proyecto. Único por cliente. |
| `CREATED_BY` | VARCHAR2(255) | No | Usuario que creó el registro. |
| `CREATED_AT` | TIMESTAMP | No | Fecha/hora de creación (default SYSTIMESTAMP). |
| `UPDATED_BY` | VARCHAR2(255) | Sí | Usuario que realizó la última modificación. |
| `UPDATED_AT` | TIMESTAMP | Sí | Fecha/hora de la última modificación. |

---

### VERSIONES_ESTIMACION

Cada versión representa una iteración de la estimación de un proyecto (negociación,
cambio de alcance, etc.). Al crearse, se copia un snapshot de todos los parámetros
globales vigentes en las tablas `ESTIMACION_PARAMETROS_*`.

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `VERSION_ESTIMACION_ID` | NUMBER IDENTITY | No | PK |
| `PROYECTO_ID` | NUMBER | No | FK → PROYECTOS |
| `NUMERO_VERSION` | NUMBER(4) | No | Número de versión dentro del proyecto. > 0. Único por proyecto. |
| `CREATED_BY` | VARCHAR2(255) | No | Usuario que creó la versión. |
| `CREATED_AT` | TIMESTAMP | No | Fecha/hora de creación (default SYSTIMESTAMP). |
| `UPDATED_BY` | VARCHAR2(255) | Sí | Usuario que realizó la última modificación. |
| `UPDATED_AT` | TIMESTAMP | Sí | Fecha/hora de la última modificación. |

---

### ELEMENTOS

Unidades a migrar dentro de una versión (un formulario `.fmb`, un reporte, un paquete
PL/SQL, etc.). Un elemento puede tener múltiples líneas de detalle si combina varias
categorías de complejidad (ej.: un formulario complejo + lógica PL/SQL simple).

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `ELEMENTO_ID` | NUMBER IDENTITY | No | PK |
| `VERSION_ESTIMACION_ID` | NUMBER | No | FK → VERSIONES_ESTIMACION. Incluido en UQ compuesto para FK compuesta desde LINEAS_DETALLE. |
| `NOMBRE` | VARCHAR2(200) | No | Nombre del archivo/unidad (ej. `OFRDM001.fmb`). Único por versión. |

---

### LINEAS_DETALLE

Cada línea asocia un elemento a una categoría de complejidad (tomada del snapshot de
la versión) y una cantidad de unidades de esa categoría.

Los FK compuestos garantizan que una línea no pueda referenciar elementos o parámetros
de una versión diferente a la que pertenece.

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `LINEA_DETALLE_ID` | NUMBER IDENTITY | No | PK |
| `ELEMENTO_ID` | NUMBER | No | FK compuesta → ELEMENTOS (VERSION_ESTIMACION_ID, ELEMENTO_ID) |
| `VERSION_ESTIMACION_ID` | NUMBER | No | Parte de ambos FK compuestos. Alinea elemento y parámetro a la misma versión. |
| `ESTIMACION_PARAM_COMPLEJIDAD_ID` | NUMBER | No | FK compuesta → ESTIMACION_PARAMETROS_COMPLEJIDAD (VERSION_ESTIMACION_ID, ESTIMACION_PARAM_COMPLEJIDAD_ID) |
| `CANTIDAD` | NUMBER(6) | No | Unidades de esta categoría para este elemento. Default 1. > 0. |

**Horas de la línea** = `CANTIDAD × HORAS` (donde HORAS viene de ESTIMACION_PARAMETROS_COMPLEJIDAD).

---

## Tablas de snapshot (parámetros congelados por versión)

### ESTIMACION_PARAMETROS_COMPLEJIDAD

Copia de PARAMETROS_COMPLEJIDAD al momento de crear la versión. Editable dentro de la
versión sin afectar otras versiones ni los globales.

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `ESTIMACION_PARAM_COMPLEJIDAD_ID` | NUMBER IDENTITY | No | PK |
| `VERSION_ESTIMACION_ID` | NUMBER | No | FK → VERSIONES_ESTIMACION. Parte de UQ compuesto para FK desde LINEAS_DETALLE. |
| `TIPO_ELEMENTO` | VARCHAR2(20) | No | `FORMULARIO`, `REPORTE`, `PLSQL`, `MENU` |
| `NIVEL_COMPLEJIDAD` | VARCHAR2(20) | Sí | `SIMPLE` … `MUY_COMPLEJO_PLUS`. NULL para MENU. |
| `HORAS` | NUMBER(6,2) | No | Horas unitarias para esta versión. > 0. |

---

### ESTIMACION_PARAMETROS_TIEMPO_ADICIONAL

Copia de PARAMETROS_TIEMPO_ADICIONAL al momento de crear la versión.

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `ESTIMACION_PARAM_TIEMPO_ADIC_ID` | NUMBER IDENTITY | No | PK |
| `VERSION_ESTIMACION_ID` | NUMBER | No | FK → VERSIONES_ESTIMACION |
| `CONCEPTO` | VARCHAR2(40) | No | `PRUEBA_FUNCIONAL`, `ADMINISTRACION`, `CONTROL_CALIDAD`, `DBA`, `DOCUMENTACION` |
| `BASE_CALCULO` | VARCHAR2(30) | No | `PROGRAMACION` o `SUBTOTAL_CONSTRUCCION` |
| `PORCENTAJE` | NUMBER(5,2) | No | >= 0. Editable por versión. |
| `ORDEN` | NUMBER(2) | No | Orden de presentación dentro de la versión. |

---

### ESTIMACION_PARAMETROS_ETAPA_CASE

Copia de PARAMETROS_ETAPA_CASE al momento de crear la versión.

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `ESTIMACION_PARAM_ETAPA_CASE_ID` | NUMBER IDENTITY | No | PK |
| `VERSION_ESTIMACION_ID` | NUMBER | No | FK → VERSIONES_ESTIMACION |
| `ETAPA` | VARCHAR2(20) | No | `ESTRATEGIA`, `ANALISIS`, `DISENO`, `CONSTRUCCION`, `TRANSICION` |
| `ORDEN` | NUMBER(2) | No | Orden secuencial. |
| `PESO_PORCENTAJE` | NUMBER(5,2) | No | >= 0. |
| `RECURSOS_PARALELOS` | NUMBER(4,2) | No | > 0. |
