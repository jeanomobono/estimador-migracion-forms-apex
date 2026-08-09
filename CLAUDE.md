# Proyecto: Aplicación APEX de estimación de horas (reemplazo de planilla Excel)

## Contexto

En Filomeni usamos una hoja de cálculo Excel para estimar las horas que va a tomar una
migración de Oracle Forms a APEX. La planilla tiene parametrizado el número de horas
aproximado según el nivel de dificultad de cada elemento a migrar (formularios simples,
semi complejos, complejos, etc.), con categorías equivalentes para reportes y para
código PL/SQL. Además tiene una región de tiempos adicionales (pruebas, reuniones, y
otros conceptos similares) y todas las fórmulas de cálculo ya resueltas.

El objetivo de este proyecto es reemplazar esa planilla por una aplicación APEX, de
forma que el proceso de estimación quede parametrizado, versionado y compartido por el
equipo, en lugar de vivir en un archivo Excel.

Este documento es la referencia persistente del proyecto: quiero que lo tengas presente
en toda la conversación, no solo como prompt inicial.

## Cómo se usa hoy la planilla (modelo de uso)

- Un **cliente** puede tener **varios proyectos**.
- Cada **proyecto** puede tener **varias versiones de estimación**, generadas a medida
  que se negocia con el cliente (la estimación cambia de alcance, de condiciones, etc.).
- Cada versión de estimación contiene líneas de detalle (formularios, reportes,
  unidades de PL/SQL) clasificadas por nivel de complejidad, más los tiempos
  adicionales de la región de pruebas/reuniones.
- Los valores de horas por complejidad y los porcentajes/tiempos adicionales son
  parámetros globales de la organización, no de un proyecto puntual — pero **una vez
  creada una versión de estimación, esa versión queda congelada con los valores de
  parámetros vigentes en ese momento**. Si más adelante cambian los parámetros
  globales, las versiones ya creadas no se recalculan; solo las versiones nuevas usan
  los valores actualizados. Esto es un requisito de diseño ya decidido, no una
  hipótesis a validar.
- La aplicación va a ser usada por varias personas de Filomeni, todas con el mismo
  rol/nivel de permisos (no hace falta un esquema de roles diferenciados tipo
  "armador vs. aprobador"). Sí conviene registrar autor y fecha de creación/edición en
  cada proyecto y cada versión de estimación, para trazabilidad.

## Restricciones técnicas y de entorno

- Motor: Oracle Database 26 FREE, instalado localmente en mi máquina.
- Aplicación: Oracle APEX 26.
- Dado que estamos en APEX 26.1+, quiero que uses **APEXlang** (el nuevo lenguaje de
  especificación declarativo de aplicaciones APEX, pensado para flujos de desarrollo
  asistidos por IA y control de versiones) como formato principal de trabajo para
  definir y exportar la aplicación, en lugar de depender solo del export SQL
  tradicional. Los artefactos `.apx` deberían quedar versionados en el repo del
  proyecto.
- La conexión a la base de datos la voy a configurar yo de forma local; no necesitás
  pedirme usuario/contraseña por chat — cuando trabajemos con la sesión de Claude Code
  ya vas a tener acceso directo al entorno.
- La aplicación tiene que ser **lo más parametrizable posible**: horas por nivel de
  complejidad, porcentajes y tiempos fijos de la región de adicionales, y cualquier
  otro valor que hoy esté "hardcodeado" en las fórmulas del Excel, debe poder
  configurarse desde la aplicación sin tocar código.
- Utiliza los ejemplos en este [repo de Github](https://github.com/oracle/apex/tree/26.1) para guiarte en la creación de los componentes de la aplicación.

## Cómo quiero que trabajes

No quiero todo de una vez. Vamos a avanzar en fases, empezando por el modelo de datos
porque sin eso no hay aplicación posible. No avances a fases siguientes sin que yo lo
pida explícitamente.

### Fase 0 — Análisis de la planilla (primer paso, antes de crear nada)

1. Voy a adjuntarte el archivo Excel de la planilla actual.
2. Analizalo en detalle: hojas, columnas, nombres reales de las categorías de
   complejidad (formularios, reportes, PL/SQL), la región de tiempos adicionales, y
   las fórmulas de cálculo.
3. Con eso, proponeme un modelo de datos conceptual (entidades, atributos,
   relaciones) — en texto o diagrama simple — **antes** de crear ninguna estructura en
   la base de datos. Quiero revisarlo y ajustarlo con vos antes de que generes DDL.

Como punto de partida, para que tengas un marco de referencia (a confirmar o corregir
una vez que veas el Excel real), la jerarquía es:

- `Cliente` → `Proyecto` (1 a N) → `Version_Estimacion` (1 a N)
- `Version_Estimacion` contiene líneas de detalle por elemento a migrar (formulario,
  reporte, unidad PL/SQL), cada una con su nivel de complejidad y las horas que le
  corresponden.
- Un conjunto de tablas de **parámetros globales vigentes**: horas por nivel de
  complejidad y por categoría (formulario/reporte/PL/SQL), y los conceptos de tiempo
  adicional (pruebas, reuniones, etc.) con su forma de cálculo (fijo, porcentaje,
  etc.).
- Cada `Version_Estimacion`, al crearse, debe copiar (snapshot) los valores de
  parámetros vigentes en ese momento, para que quede congelada aunque los parámetros
  globales cambien después.

No asumas que esta jerarquía es exacta ni que agota los conceptos de la planilla —
puede haber matices que solo se ven en el Excel real (por ejemplo, si "reportes" y
"PL/SQL" usan exactamente las mismas categorías de complejidad que los formularios, o
si tienen las propias).

### Fase 1 — Modelo de datos

Una vez que acordemos el modelo conceptual:

- Generá el DDL completo (tablas, claves primarias/foráneas, secuencias o columnas
  identity, constraints de integridad razonables).
- Incluí datos de referencia iniciales (parámetros de complejidad y de tiempos
  adicionales) tomados de los valores actuales del Excel, como carga inicial.
- Proponé una convención de nombres para tablas/columnas (prefijo, singular/plural,
  etc.) y decime cuál vas a usar antes de aplicar el DDL, para que la revisemos juntos
  la primera vez.
- Documentá el modelo final (puede ser un diccionario de datos simple en Markdown)
  dentro del repo del proyecto.

### Fases siguientes — módulo por módulo

Una vez validado el modelo de datos, vamos a ir construyendo la aplicación APEX de a
un módulo por vez (por ejemplo: administración de parámetros, gestión de
clientes/proyectos, carga de líneas de una estimación con cálculo automático,
comparación entre versiones, exportación de la estimación para el cliente, etc.). No
definas ni construyas estos módulos todavía — los vamos a ir alcanzando y precisando a
medida que avancemos.

## Qué me falta darte para arrancar

- El archivo Excel de la planilla actual (lo adjunto en la sesión de trabajo).
- Confirmar el nombre del workspace/aplicación APEX a usar.
- Cualquier convención de nomenclatura de esquema/tablas que ya usemos en otros
  proyectos de Filomeni, si aplica (si no la tengo clara, proponela vos en la Fase 1).