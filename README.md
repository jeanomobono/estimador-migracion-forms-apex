# Estimador de Migraciones Forms → APEX

Aplicación Oracle APEX que reemplaza la planilla Excel usada en Filomeni para estimar el esfuerzo de migraciones de Oracle Forms a APEX. Permite parametrizar, versionar y compartir las estimaciones en equipo.

## Stack tecnológico

| Componente | Versión |
|---|---|
| Oracle Database | 23ai FREE (local) |
| Oracle APEX | 26.1 |
| Formato de la app | APEXlang (`.apx`) |
| Cliente de base de datos | SQLcl 26.1.2+ |
| Tooling APEXlang (validación) | Node.js v18+ |

## Estructura del repositorio

```
estimador-migraciones-forms-apex/   # Fuente de la app en formato APEXlang
  application.apx                   # Definición global: navegación, tema, autenticación
  pages/                            # Una página por archivo
  shared-components/                # LOVs, listas, breadcrumbs, tema
  workspace-components/             # Config del workspace (no se versiona en imports)
  .apex/apexlang.json               # Versión del formato APEXlang

db/
  schema.sql                        # DDL completo: tablas, índices, triggers, PKG_ERROR_HANDLER
                                    # + datos de referencia iniciales (parámetros de complejidad)

xlsx/
  planilla_estimacion.xlsx          # Template de la planilla Excel original (solo referencia)
```

## Modelo de datos (resumen)

```
clientes → proyectos → versiones_estimacion
                              │
                    ┌─────────┴─────────┐
              elementos           estimacion_parametros_*
                  │               (snapshot de parámetros
            lineas_detalle         al crear la versión)
```

Cada versión de estimación congela una copia de los parámetros globales vigentes al momento de su creación (horas por complejidad, etapas CASE, tiempos adicionales), de modo que cambios posteriores en los parámetros no afectan versiones ya creadas.

## Módulos de la aplicación

| Página(s) | Módulo |
|---|---|
| p100 | Administración de parámetros globales |
| p200 / p201 | Listado y formulario de clientes (con IG de contactos) |
| p210 / p211 | Proyectos del cliente / formulario de proyecto |
| p220 | Versiones de estimación de un proyecto |
| p221 | Detalle de versión: elementos, líneas y resumen de horas |

## Prerequisitos

- Oracle Database 23ai FREE instalado localmente
- Oracle APEX 26.1 configurado en el mismo servidor
- SQLcl 26.1.2 o superior (`sql` en el PATH)
- Node.js v18+ (para el CLI de validación APEXlang `apexctl.mjs`)
- Workspace APEX creado con schema `ESTIMADOR` asignado

## Setup inicial

### 1. Crear el schema y los objetos de base de datos

Conectarse como DBA y crear el usuario si no existe:

```sql
create user estimador identified by <password>
    default tablespace users
    quota unlimited on users;
grant connect, resource to estimador;
grant apex_administrator_role to estimador;  -- si se usa como workspace schema
```

Luego, conectado como `ESTIMADOR`, ejecutar el DDL completo:

```bash
sql estimador/<password>@localhost:1521/freepdb1 @db/schema.sql
```

Esto crea las 13 tablas, índices, triggers de auditoría, el paquete `PKG_ERROR_HANDLER` y carga los datos de referencia iniciales.

### 2. Importar la aplicación APEX

```bash
# Copiar la app excluyendo workspace-components (contiene config local del workspace)
rm -rf /tmp/apex-import
rsync -a --exclude='workspace-components' \
    estimador-migraciones-forms-apex/ /tmp/apex-import/

# Importar sobre la app existente (App ID 100)
# Reemplazar <workspace_id> con el ID numérico del workspace ESTIMADOR
sql /nolog <<EOF
connect sys/<password>@localhost:1521/freepdb1 as sysdba
apex import -input /tmp/apex-import -workspaceid <workspace_id> -id 100
EOF
```

Para obtener el `workspace_id`:

```sql
select workspace_id from apex_workspaces where workspace = 'APPS';
```

## Flujo de trabajo APEXlang

Los archivos `.apx` son la **fuente de verdad** versionada. Después de cualquier cambio hecho desde el APEX Builder, hay que sincronizar:

```bash
# Exportar la app actualizada en formato APEXlang
apex export -applicationid 100 \
    -exptype APEXLANG \
    -split \
    -dir estimador-migraciones-forms-apex \
    -overwrite-files
```

Luego revisar el diff y commitear los archivos modificados.

### Validación local (opcional)

El paquete de skills en `.agents/skills/apex/apexlang/` incluye `tools/apexctl.mjs` para validar la sintaxis APEXlang sin hacer un import completo:

```bash
cd .agents/skills/apex/apexlang
node tools/apexctl.mjs validate ../../../../estimador-migraciones-forms-apex
```

## Notas de diseño

- **Parámetros congelados**: al crear una `version_estimacion`, se copia el estado vigente de `parametros_complejidad`, `parametros_etapa_case` y `parametros_tiempo_adicional` en las tablas `estimacion_parametros_*`. Las versiones existentes no se recalculan si cambian los parámetros globales.
- **Auditoría**: todos los cambios registran `created_by` / `created_at` / `updated_by` / `updated_at` via triggers BI/BU que leen el usuario de sesión APEX (`SYS_CONTEXT('APEX$SESSION','APP_USER')`).
- **Mensajes de error amigables**: el paquete `PKG_ERROR_HANDLER` mapea errores de constraint ORA- a mensajes en español, registrado como error handler de la aplicación.
