# Manejo de Errores a Nivel de Aplicación — Spec

## Objetivo

Reemplazar los mensajes de error crípticos de Oracle (ORA-02290, ORA-02292, etc.) con mensajes en español legibles para el usuario, para todos los errores de base de datos que puedan ocurrir en cualquier página de la aplicación APEX.

## Decisiones de diseño

- **Enfoque:** Función de manejo de errores a nivel de aplicación (Application Error Handling Function), no validaciones por página.
- **Cobertura:** Todos los check constraints con nombre propio + todos los FK constraints que protegen integridad referencial.
- **Sin tabla de lookup:** El mapeo constraint → mensaje se implementa con un `CASE` en PL/SQL. Los nombres de constraint son estables y la lista es corta.
- **Display location:** `apex_error.c_inline_in_notification` para todos los errores — aparece como notificación en la parte superior de la región/página. No se intenta resaltar columnas específicas en IGs.
- **Errores no mapeados:** Mensaje genérico amigable; el detalle técnico va a `additional_info` (visible solo en modo debug).

## Archivos involucrados

| Archivo | Acción |
|---|---|
| `db/migrations/002_error_handler.sql` | Crear — DDL del package `ESTIMADOR.PKG_ERROR_HANDLER` |
| `estimador-migraciones-forms-apex/application.apx` | Modificar — agregar bloque `errorHandling` |

## Package PL/SQL

**Nombre:** `ESTIMADOR.PKG_ERROR_HANDLER`

**Función pública:**
```sql
FUNCTION handle_error(p_error IN apex_error.t_error)
    RETURN apex_error.t_error_result
```

**Lógica:**
1. Si `p_error.ora_sqlcode` es -2290 (check constraint) o -2292 (FK parent key), buscar `p_error.constraint_name` en el CASE.
2. Si se encuentra: devolver mensaje amigable con `display_location = apex_error.c_inline_in_notification`.
3. Si no se encuentra: devolver mensaje genérico, y pasar el error técnico completo a `additional_info`.
4. Para cualquier otro tipo de error: ídem fallback.

## Registro en APEX

En `application.apx`, agregar dentro de la definición del app:

```apexlang
errorHandling {
    errorHandlingFunction: ESTIMADOR.PKG_ERROR_HANDLER.handle_error
}
```

## Mapeo completo de constraints

### Check constraints

| Constraint | Tabla | Mensaje |
|---|---|---|
| `CK_PARAM_COMPLEJIDAD_HORAS` | `PARAMETROS_COMPLEJIDAD` | Las horas deben ser un número mayor a 0 |
| `CK_PARAM_ETAPA_CASE_PESO` | `PARAMETROS_ETAPA_CASE` | El peso no puede ser negativo |
| `CK_PARAM_ETAPA_CASE_RECUR` | `PARAMETROS_ETAPA_CASE` | Los recursos paralelos deben ser un número mayor a 0 |
| `CK_PARAM_TIEMPO_ADIC_PCT` | `PARAMETROS_TIEMPO_ADICIONAL` | El porcentaje no puede ser negativo |
| `CK_EST_PARAM_COMPLEJIDAD_HORAS` | `ESTIMACION_PARAMETROS_COMPLEJIDAD` | Las horas deben ser un número mayor a 0 |
| `CK_EST_PARAM_ETAPA_CASE_PESO` | `ESTIMACION_PARAMETROS_ETAPA_CASE` | El peso no puede ser negativo |
| `CK_EST_PARAM_ETAPA_CASE_RECUR` | `ESTIMACION_PARAMETROS_ETAPA_CASE` | Los recursos paralelos deben ser un número mayor a 0 |
| `CK_EST_PARAM_TIEMPO_ADIC_PCT` | `ESTIMACION_PARAMETROS_TIEMPO_ADICIONAL` | El porcentaje no puede ser negativo |
| `CK_LINDET_CANTIDAD` | `LINEAS_DETALLE` | La cantidad debe ser un número mayor a 0 |
| `CK_VERSIONES_EST_NUMERO` | `VERSIONES_ESTIMACION` | El número de versión debe ser mayor a 0 |

### FK constraints

| Constraint | Mensaje |
|---|---|
| `FK_PROYECTOS_CLIENTE` | No se puede eliminar el cliente porque tiene proyectos asociados |
| `FK_VERSIONES_EST_PROYECTO` | No se puede eliminar el proyecto porque tiene versiones de estimación asociadas |
| `FK_ELEMENTOS_VERSION` | No se puede eliminar la versión porque tiene elementos de migración cargados |
| `FK_LINDET_ELEMENTO` | No se puede eliminar el elemento porque tiene líneas de detalle asociadas |
| `FK_LINDET_PARAM_COMPLEJIDAD` | No se puede eliminar este parámetro porque está en uso en estimaciones existentes |
| `FK_EST_PARAM_COMPLEJIDAD_VER` | No se puede eliminar la versión porque tiene parámetros de complejidad asociados |
| `FK_EST_PARAM_ETAPA_CASE_VER` | No se puede eliminar la versión porque tiene parámetros de etapa CASE asociados |
| `FK_EST_PARAM_TIEMPO_ADIC_VER` | No se puede eliminar la versión porque tiene parámetros de tiempo adicional asociados |

### Fallback (cualquier otro error de DB)

> Se produjo un error al guardar los datos. Por favor, revisá los valores ingresados e intentá de nuevo.

## Restricciones técnicas

- Oracle Database 26 FREE, schema `ESTIMADOR`
- Oracle APEX 26 — `apex_error` API disponible
- Conexión MCP sqlcl: `estimador_freepdb1`
- Artefactos APEXlang se versionan en `estimador-migraciones-forms-apex/`
