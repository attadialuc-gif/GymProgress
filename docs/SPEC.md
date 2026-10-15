# Especificación original del producto

Copia de la especificación entregada por el usuario (fuente de requisitos). Si algo de los demás documentos contradice este archivo, manda este archivo; dentro de él, manda la sección 2.

---

# Proyecto: app de gimnasio con asistente de sobrecarga progresiva (iPhone)

## 0. Cómo leer este documento

- **Idioma:** la UI y la documentación van en español (es-AR). El código, los identificadores, los nombres de tests y los mensajes de commit van en inglés.
- **Prioridades si algo entra en conflicto** (de mayor a menor):
  1. Integridad de los datos (nunca perder un entrenamiento).
  2. **Sistema de sobrecarga progresiva (sección 2):** tiene prioridad sobre cualquier función secundaria de la app.
  3. Velocidad de registro durante el entrenamiento.
  4. Todo lo demás (estadísticas, estética, funciones secundarias).
- **Nombre de trabajo de la app:** `GymProgress` (placeholder, configurable en un solo lugar). No lo consultes: usalo y seguí.

---

## 1. Contexto y objetivo del producto

Quiero una aplicación de gimnasio **nativa para iPhone**, funcional, rápida, offline y de calidad comercial, pensada para acompañar el entrenamiento durante años. No quiero una propuesta, un prototipo estático ni pantallas de ejemplo: quiero una app real con persistencia, navegación, cálculos reales y arquitectura extensible.

**Propósito central: ser un asistente de sobrecarga progresiva.** La app distingue entre *registrar lo que el usuario hizo* (la base de datos) y *asistirlo para decidir qué hacer en la próxima sesión* (el producto). Estadísticas, calendario, rachas, récords y volumen complementan ese sistema; no lo desplazan.

Lentes de trabajo (no hace falta "actuar" como un equipo; aplicá estos criterios al decidir):

- **iOS senior:** SwiftUI idiomático, concurrencia segura, rendimiento, ciclo de vida de la app.
- **UX/UI fitness premium:** registro con una mano, entre series, con el menor número de toques.
- **Datos y arquitectura:** modelo normalizado, identificadores estables, migraciones, historial inmutable.
- **Preparación física basada en evidencia:** doble progresión, autorregulación por RIR/RPE, individualización. Sin afirmaciones médicas ni "números ideales" universales de series o repeticiones.

La app responde estas preguntas:

1. ¿Estoy progresando realmente?
2. ¿Cuánto peso y cuántas repeticiones hice la última vez?
3. ¿Qué peso debería intentar en mi próxima sesión, y por qué?
4. ¿Cómo evolucionó mi fuerza en la semana, el mes, el trimestre y el año?
5. ¿Cuánto volumen acumulo por grupo muscular?
6. ¿Cuántos días entrené y qué tan constante soy?
7. ¿Qué ejercicios, rutinas y músculos progresan más?
8. ¿Cuáles son mis récords y objetivos pendientes?

---

## 2. REQUISITOS CRÍTICOS DEL SISTEMA DE SOBRECARGA PROGRESIVA

**Esta sección tiene prioridad sobre cualquier función secundaria de la aplicación.** Si hay que elegir entre pulir estadísticas, calendario o cualquier extra y cumplir esta sección, se cumple esta sección. Las secciones 8.2 (especificación del motor), 7 (modelo de datos), 10 (registro), 13 (pruebas) y 14 (etapas) están alineadas con lo que sigue; si encontrás una discrepancia, **manda esta sección**.

### 2.A. La recomendación debe ser visible y accionable

Al abrir cada ejercicio durante una sesión, mostrar **en primer plano** (arriba de la tabla de series, sin menús ni pestañas intermedias):

- Peso utilizado en la última sesión comparable.
- Repeticiones realizadas en cada serie de esa sesión.
- Objetivo de la sesión actual (series y rango de repeticiones, RIR objetivo si existe).
- Peso y repeticiones recomendados.
- Motivo de la recomendación (una o dos líneas).
- Botones para **aceptar, modificar o ignorar** la sugerencia.

Comportamiento de los botones:

- **Aceptar:** precarga el peso recomendado en las series y deja las repeticiones objetivo como referencia visible.
- **Modificar:** editor rápido (peso y repeticiones objetivo, con +/− según el incremento del ejercicio). Los valores resultantes se usan como objetivo de esa sesión.
- **Ignorar:** no precarga nada de la recomendación; el usuario puede copiar las cargas anteriores con un toque.
- En los tres casos se **persiste la decisión** (ver `RecommendationDecision` en la sección 7). Nunca se pierde, ni siquiera si se cierra la app.

No obligues al usuario a navegar por gráficos o estadísticas para descubrir qué debería intentar hacer. Un resumen de las recomendaciones también aparece en la vista previa de la rutina y en Inicio, pero la vista de ejercicio es el lugar canónico.

### 2.B. Reglas de progresión verificables

Implementá un **motor de progresión independiente de la interfaz** (en `GymCore`, función pura, sin SwiftUI ni SwiftData). Para la estrategia predeterminada de **doble progresión**:

- Si el usuario todavía no alcanza el extremo superior del rango de repeticiones, recomendar **mantener la carga e intentar progresar en repeticiones**, siempre que sea compatible con el esfuerzo objetivo.
- Si alcanza el extremo superior **en todas las series** y cumple el RIR objetivo cuando se haya registrado, **evaluar un aumento de carga** adecuado al ejercicio (equipamiento e incrementos reales, no un porcentaje fijo).
- Si **no hay información suficiente sobre el esfuerzo** (RIR/RPE no registrado), mostrar una **recomendación condicionada** en lugar de asumir que la técnica y el esfuerzo fueron adecuados. Ejemplo de texto: "Podrías subir a 62,5 kg si las series se hicieron con buena técnica y cerca del esfuerzo objetivo".
- Si el rendimiento disminuye, **revisar el historial antes de recomendar una reducción de carga**; nunca reducir ni aumentar automáticamente por una sola sesión.
- Si los resultados fluctúan, **evitar declarar un estancamiento a partir de una sola sesión** (mínimo 3 sesiones comparables).
- Si cambia el ejercicio, la máquina, la variante o una condición relevante, **no comparar automáticamente los resultados como si fueran equivalentes** (ver "contexto de comparabilidad" en la sección 8.1).

El usuario debe poder **modificar los criterios de progresión por ejercicio**: rango de repeticiones, series objetivo, RIR objetivo, incremento, pesos disponibles, sesiones consecutivas requeridas y estrategia. La estrategia se modela como un protocolo (`ProgressionStrategy`) con doble progresión como implementación por defecto, de modo que se puedan agregar otras sin tocar la UI.

La especificación detallada de reglas, orden de evaluación y salida está en la sección 8.2.

### 2.C. Recomendaciones basadas en datos reales

- **Nunca inventes** sesiones anteriores, pesos, récords ni resultados.
- Cuando no haya historial suficiente, la app lo dice ("Todavía no hay datos suficientes para recomendar una carga") y **permite configurar un objetivo inicial** (peso inicial y rango). No se muestra ninguna cifra inventada.
- Las recomendaciones son **deterministas**: con las mismas condiciones y los mismos datos de entrada, la salida es idéntica. Para garantizarlo, el motor no usa aleatoriedad, no lee el reloj (el "ahora" se inyecta) y no depende del orden del arreglo de entrada (ordena internamente de forma estable). Esto se verifica con tests unitarios.

### 2.D. Pruebas obligatorias del sistema de progresión

Implementá pruebas automatizadas que comprueben, **como mínimo**, estos ocho casos. Los valores del ejemplo usan: 3 series, rango 8–12, RIR objetivo 2, incremento 2,5 kg. Adaptalos si hace falta, pero cada caso debe tener entrada y salida esperada escritas a mano.

| # | Caso | Entrada (ejemplo) | Salida esperada |
|---|---|---|---|
| 1 | Todavía no se alcanza el rango superior | 60 kg × 10, 9, 8 | Mantener 60 kg; objetivo de repeticiones +1 en las series por debajo del máximo; motivo "rango superior no alcanzado". |
| 2 | Se alcanza el rango superior en todas las series | 60 kg × 12, 12, 12, RIR 2, 2, 2 | Aumentar al siguiente peso disponible (62,5 kg); repeticiones objetivo vuelven hacia el mínimo del rango; confianza alta. Sin RIR registrado: misma sugerencia pero **condicionada**. |
| 3 | Repeticiones cumplidas pero no el RIR previsto | 60 kg × 12, 12, 12, RIR 0, 0, 1 | **No** aumentar; mantener y explicar que el esfuerzo estuvo por encima del objetivo. |
| 4 | Rendimiento inferior al anterior | Antes 12, 11, 10; ahora 10, 9, 8 al mismo peso | Mantener y mostrar el historial; **sin reducción automática**; si ocurre en 2 sesiones comparables consecutivas con series bajo el mínimo, sugerir reevaluar. |
| 5 | Ejercicio nuevo sin historial | Sin sesiones | "Datos insuficientes"; pedir objetivo inicial; si el usuario lo configuró, recomendarlo con motivo "objetivo inicial". Nunca inventar un peso. |
| 6 | Cambio en los incrementos de peso disponibles | 60 kg × 12, 12, 12 con incremento 2,5 → 62,5; con 5 → 65; con lista de pesos disponibles [60, 62, 64] → 62; sin peso superior disponible → mantener con aviso | La recomendación respeta el incremento y los pesos disponibles vigentes; el cambio de configuración **no altera sesiones pasadas**. |
| 7 | Series incompletas | 12, 12 y la tercera serie pendiente o no realizada; o menos series completadas que las objetivo | **No** aumentar; mantener; objetivo: completar todas las series. Una serie pendiente nunca se interpreta como cero repeticiones. Un ejercicio sin series completadas no es sesión comparable. |
| 8 | Modificación manual de la recomendación | El motor recomienda 62,5 kg × 8; el usuario modifica a 61 kg | Se persiste una `RecommendationDecision` (recomendado vs. final, tipo `modified`, fecha). Tras cerrar y reabrir (contenedor recargado) la modificación sigue ahí; recalcular o volver a entrar a la pantalla **no la pisa**; la recomendación de la sesión siguiente se calcula con lo **realmente realizado**, no con el objetivo manual. |

Además, tests de **determinismo** (misma entrada dos veces → misma salida, y entrada permutada → misma salida) y de **no comparabilidad** (cambio de máquina o variante → sin comparación automática). Verificá que cada caso produzca la recomendación esperada y que los cambios manuales no se pierdan.

### 2.E. Prioridad de implementación: primero el flujo de punta a punta

Antes de construir todas las estadísticas, integraciones y funciones secundarias, completá un **flujo funcional de principio a fin**:

> Crear rutina → seleccionar ejercicio → definir objetivo → registrar series → guardar la sesión → consultar el historial → recibir la recomendación para la próxima sesión.

Este flujo debe funcionar **con datos persistentes y pruebas satisfactorias** antes de ampliar el producto. Es la puerta de calidad de la etapa 3 (sección 14): no se empieza con calendario, estadísticas avanzadas, volumen por músculo ni extras hasta que ese flujo pase.

**No consideres completado el sistema de sobrecarga progresiva** hasta que las recomendaciones se calculen a partir de los datos registrados y se hayan verificado sus reglas con las pruebas de la sección 2.D.

---

## 3. Modo de trabajo

**Autonomía.** Trabajá de punta a punta sin pedirme confirmación en cada etapa. Solo frená a preguntarme si ocurre alguna de estas tres cosas: (a) una decisión irreversible o destructiva, (b) un bloqueo de entorno que no podés resolver vos, (c) una contradicción real en los requisitos. En cualquier otro caso elegí la opción más razonable, registrala en `docs/DECISIONS.md` (decisión, alternativas, motivo) y seguí.

**Planificación.** Antes de cada etapa, planificá brevemente. Dentro de cada etapa, trabajá en pasos chicos y verificables.

**Verificación y honestidad (obligatorias).**
- Una función solo está "terminada" si tiene lógica funcional **y** fue ejecutada o testeada. Una interfaz sin lógica no cuenta.
- Nunca digas que algo compila o que los tests pasan sin haber ejecutado el comando. En los informes de cada etapa pegá el comando y el resultado resumido.
- Si una herramienta, cuenta o entorno no está disponible, decí exactamente qué falta, y seguí con todo lo que sí se pueda hacer y verificar.
- No inventes datos, APIs, integraciones ni resultados. Ninguna función externa se simula (Apple Health, sincronización, widgets, etc.): o está implementada o está marcada como "preparada, no implementada".

**Memoria del proyecto.** `CLAUDE.md` corto en la raíz (stack, estructura, comandos, convenciones, reglas persistentes incluyendo un resumen de la sección 2). `docs/PROGRESS.md` actualizado al cerrar cada etapa. Git con `.gitignore` para Xcode/Swift y un commit por etapa o hito.

**Revisión independiente.** Al cerrar las etapas 1, 2 y 3 lanzá un subagente revisor, sin el contexto de la implementación, que audite el motor de progresión, los cálculos, la persistencia y el flujo de punta a punta contra la sección 2 y la sección 8. Corregí lo que encuentre antes de avanzar.

---

## 4. Etapa 0: inspección del entorno

Ejecutar y registrar en `docs/ENVIRONMENT.md` (`uname -a ; sw_vers`, `xcodebuild -version ; xcode-select -p`, `swift --version`, `xcrun simctl list devices available`, `which xcodegen tuist swiftlint`, `git --version`) y decidir:

| Situación | Qué hacer |
|---|---|
| macOS + Xcode + simulador de iPhone | Camino completo: proyecto iOS, compilar con `xcodebuild` para simulador, correr tests en simulador. |
| macOS sin Xcode completo, o sin simulador | Desarrollá todo el código y el paquete de dominio; verificá lo que se pueda con `swift build` / `swift test`; indicá exactamente qué falta instalar. |
| Linux u otro sistema sin Xcode | Implementá el núcleo de dominio como Swift Package puro (sin dependencias de Apple) y verificalo con `swift test`. Escribí también la capa SwiftUI/SwiftData sin poder compilarla y marcá explícitamente esa parte como **no verificada**. |

Generación del proyecto: preferir **XcodeGen** (`project.yml`). Al terminar la etapa 0, escribir `docs/ARCHITECTURE.md`, el modelo de datos, las reglas de cálculo (sección 8) y la lista de etapas, y continuar con la etapa 1.

---

## 5. Decisiones técnicas por defecto

- **Plataforma:** iOS 17+, iPhone, orientación vertical.
- **Lenguaje/UI:** Swift y SwiftUI. Observation (`@Observable`) para estado de vista.
- **Persistencia:** SwiftData, con `VersionedSchema` y un plan de migración desde la primera versión.
- **Gráficos:** Swift Charts.
- **Dependencias de terceros en runtime:** ninguna.
- **Red:** ninguna. Cero analytics, cero telemetría. Incluir `PrivacyInfo.xcprivacy` coherente.
- **Localización:** es-AR como idioma base mediante String Catalogs. Formateo con `Locale`/`FormatStyle`.
- **Entrada numérica:** los pesos aceptan coma o punto decimal y se almacenan normalizados.
- **Semana:** comienza el lunes por defecto, configurable.
- **Unidades:** kg y cm; internamente siempre kg; lb solo de presentación.

---

## 6. Arquitectura

```
GymCore/        Swift Package puro, sin SwiftUI ni SwiftData. Testeable en cualquier plataforma.
  Models/ Progression/ Metrics/ Consistency/
App/
  Persistence/  modelos @Model de SwiftData, repositorios, migraciones, seeders, mapeo a/desde GymCore
  Features/     Home, Routines, Workout, Progress, Profile (vista + view model por feature)
  Services/     RestTimerService, NotificationService, ExportService, HapticsService
  DesignSystem/
Tests/
  GymCoreTests/ cálculos y progresión (incluye los 8 casos obligatorios)
  App tests/    persistencia (ModelContainer en memoria y recargado), recuperación de sesión, decisiones, export
```

Reglas: cálculos de progresión y métricas **solo** en `GymCore`, funciones puras y deterministas ("ahora" inyectado). Las vistas no contienen lógica de negocio. Repositorios ocultan SwiftData detrás de protocolos. Componentes reutilizables en `DesignSystem`.

---

## 7. Modelo de datos

Diferenciar **catálogo/plantillas** de **historial**. El historial es inmutable respecto de ediciones posteriores del catálogo.

| Entidad | Campos clave y notas |
|---|---|
| `Exercise` | id (UUID estable), nombre, tipo de medición (`weightReps` / `bodyweightReps` / `duration`), equipamiento, `loadMode` (`total` / `perSide`), músculos principales y secundarios (con factor), incremento por defecto, pesos disponibles opcionales, `isCustom`, `isArchived`. |
| `ProgressionConfig` | Por ejercicio (y overrideable por `RoutineExercise`): estrategia, series objetivo, repMín, repMáx, RIR objetivo opcional, peso inicial, incremento, pesos disponibles, sesiones consecutivas requeridas, días de pausa para reevaluar. |
| `RoutineTemplate` | id, nombre, orden, notas, `isArchived`. |
| `RoutineExercise` | plantilla, ejercicio, orden, grupo de superserie/biserie, series objetivo, rango, descanso, RIR objetivo, notas/técnica, override de `ProgressionConfig`. |
| `ScheduleEntry` | día de la semana, rutina, **`validFrom`** (y `validTo` opcional). Cambiar el calendario crea una entrada nueva; nunca reescribe las anteriores. |
| `WorkoutSession` | id, inicio, fin, intervalos de pausa, estado (`active` / `paused` / `completed` / `discarded`), rutina + **snapshot del nombre**, notas, `isAtypical`. |
| `ExerciseLog` | sesión, ejercicio + **snapshot** (nombre, músculos, medición, `loadMode`, `ProgressionConfig` vigente), **contexto de comparabilidad** (`variantLabel`, `equipmentLabel`), `orderIndex` real de ejecución, notas, y la **recomendación calculada al abrir el ejercicio, congelada**. |
| `RecommendationDecision` | `exerciseLog`, recomendación original (acción, peso, reps, motivo, condicionada o no), decisión (`accepted` / `modified` / `ignored`), valores finales, `decidedAt`. Fuente de verdad de lo que eligió el usuario; el motor nunca la sobrescribe. |
| `SetLog` | índice, tipo (`warmup` / `working`; extensible), peso, reps o segundos, peso adicional/asistencia, RIR, RPE, estado (`pending` / `completed`), `completedAt`. |
| `ComparabilityLink` | Vínculo manual "tratar como equivalente" entre contextos. Solo si el usuario lo crea. |
| `Goal` | ejercicio, métrica, valor, fecha opcional, estado. |
| `PersonalRecord` | ejercicio, tipo, valor, fecha, `SetLog`, `isEstimated`. Derivable/recalculable. |
| `UserSettings` | unidades, inicio de semana, descanso por defecto, tema, objetivo semanal, modo de constancia, factor de series indirectas, fórmula de 1RM, tope de reps para 1RM, series mínimas para sesión válida. |
| `BodyWeightEntry` | (preparada, opcional, fuera del MVP). |

Garantías: borrar o archivar un ejercicio o rutina **nunca** borra ni altera sesiones pasadas; eliminar de verdad solo sin historial y con confirmación. Cambiar la `ProgressionConfig` **no reescribe** snapshots. UUID estables. Exportación con DTOs `Codable` + `schemaVersion` (incluye decisiones y vínculos).

---

## 8. Especificación de cálculos

### 8.1 Definiciones base
- **Serie efectiva:** `working` + `completed` (peso y reps válidos). Calentamiento no cuenta. Una `pending` nunca es cero.
- **Contexto de comparabilidad:** `(exerciseId, variantLabel, equipmentLabel, loadMode)`. Comparables solo si coincide **o** hay `ComparabilityLink`. Si cambia, el motor responde "sin datos comparables en este contexto"; la UI puede mostrar el otro contexto solo como referencia **"no equivalente"**, con opción de "tratar como equivalente".
- **Sesión comparable:** `completed`, ≥ 1 serie efectiva de ese ejercicio, mismo contexto, sin `isAtypical`. Se prioriza la última.
- **Peso de trabajo:** peso más frecuente entre las series efectivas (empate → el mayor).
- **Volumen de carga:** Σ(peso × reps) efectivas; bodyweight con peso corporal conocido: (pc + adicional − asistencia) × reps, si no solo carga externa (indicado); `perSide`: definir y mostrar si es por lado o total.
- Diferenciar peso utilizado, volumen externo, series realizadas y fuerza estimada (1RM).

### 8.2 Motor de doble progresión
Entradas: `ProgressionConfig` + historial comparable + decisión previa (si existe) + fecha inyectada. Reglas en orden:
1. Sin historial comparable → `needsInitialTarget` ("Todavía no hay datos suficientes"); con peso inicial configurado, recomendarlo con motivo "objetivo inicial".
2. Pausa larga (> N días, default 21) → no aumentar; sugerir **reevaluar**.
3. Series incompletas → sin aumento; mantener y completar todas.
4. Subir peso: todas las series ≥ repMáx al mismo peso durante las sesiones consecutivas requeridas (default 1) **y** (RIR ≥ objetivo o sin objetivo). Siguiente peso disponible real; si no existe, mantener con aviso. Reps → repMín. Sin RIR/RPE y con objetivo → **condicionada**.
5. Mantener por esfuerzo: repMáx alcanzado pero RIR < objetivo → no subir.
6. Subir reps: todas ≥ repMín y alguna < repMáx → mismo peso, +1 en las series bajo el máximo (empezando por las más bajas), si es compatible con el esfuerzo.
7. Rendimiento inferior → mantener, mostrar historial; nunca reducir/aumentar por una sola sesión. Series < repMín en **2 sesiones comparables consecutivas** → `reassess`.
8. Tendencia (≥ 3 sesiones): progresando / estable / posible estancamiento / descenso; con fluctuación o < 3 sesiones no declarar estancamiento.
9. `bodyweightReps` reps y luego peso adicional; `duration` segundos; `perSide` redondea con los pesos disponibles.

Salida `Recommendation`: action, peso, reps por serie, reasonCode, texto en español, confidence (`high`/`conditional`), conditions, evidencia, contexto. Determinista y explicable; se puede aceptar/modificar/ignorar y se persiste; se calcula al abrir el ejercicio con el historial **previo** y se congela; la sesión actual alimenta recomendaciones **futuras**.

### 8.3 1RM: Epley por defecto, Brzycki alternativa; rotulado estimación; excluir series > X reps (default 10) y exclusión manual; distinguir récords reales de calculados.
### 8.4 Volumen por músculo: series directas; indirectas × factor (0,5) mostradas por separado; frecuencia semanal; objetivos individuales configurables.
### 8.5 Constancia: sesión válida (completed + ≥ N series, N = 3); Modo A por cumplimiento del plan semanal (`ScheduleEntry` vigente en esa fecha; descansos programados no son fallos); Modo B por días consecutivos con separación ≤ K (2). Mostrar modo y definición.
### 8.6 Fechas: instantes UTC; día/semana con el `Calendar` del usuario. Tests: DST, cambio de zona, medianoche, inicio de semana, fin de mes y año.

---

## 9. Pantallas (5 pestañas)
9.1 Inicio (próximo entrenamiento, semana y objetivo, racha, récords, volumen, última sesión, **recomendaciones para el próximo entrenamiento**). 9.2 Rutinas (CRUD, duplicar, reordenar, superseries, criterios de progresión por ejercicio, plantillas iniciales editables; biblioteca JSON versionada de 80–120 ejercicios en español, ampliable sin perder los propios). 9.3 Entrenamiento (sección 10). 9.4 Progreso (filtros de período, ejercicio, rutina, músculo; gráficos con datos reales; definiciones accesibles; nunca necesaria para saber qué hacer hoy). 9.5 Calendario (mensual/semanal, planificado/completado/omitido/descanso, `validFrom`). 9.6 Récords y objetivos (real vs estimado). 9.7 Perfil y ajustes.

## 10. Registro de entrenamiento
Tarjeta de recomendación en primer plano (2.A). Tabla por ejercicio (serie, peso, reps, RIR/RPE, tipo, estado, sesión anterior al lado). Obligatorio: editar todo, agregar/quitar series, pesos distintos, copiar cargas anteriores con un toque, decimales con coma o punto, +/− con el incremento, mancuernas/barras/máquinas/poleas/peso corporal (adicional y asistencia), cambio de máquina/variante con un gesto, completar serie en un toque con háptico + temporizador de descanso automático basado en marcas de tiempo (sobrevive al background) + notificación local (permiso en contexto) + mantener pantalla encendida, pausar/reanudar/finalizar con tiempo descontando pausas, modificar la rutina solo para esa sesión y registrar el orden real, notas por sesión y ejercicio, marcar atípico, **guardado automático** en cada cambio relevante (incluida la decisión de recomendación), **recuperación** de sesión `active`/`paused` sin pérdida (incluidas las decisiones), validaciones (no negativos; advertencia ante valores inusuales), confirmación antes de descartar/borrar.

## 11. Diseño
Premium, minimalista, deportivo, nativo. Oscuro por defecto (con claro/sistema). Números grandes. La tarjeta de recomendación es el elemento más destacado. Un color de acento. Dynamic Type, VoiceOver (recomendación y botones totalmente accesibles), contraste, Reducir movimiento.

## 12. Fiabilidad y privacidad
100 % offline. Nunca perder datos. Export JSON (y CSV) con `schemaVersion`; import validado sin duplicar. Backups sobre el mismo mecanismo. Sin secretos. Datos demo solo `#if DEBUG`.

## 13. Pruebas
Progresión: 8 casos + determinismo + no comparabilidad (TDD). GymCore golden: pausa larga, una sesión mala, mancuernas discretas, peso corporal, duración, atípica, `ComparabilityLink`; tendencias < 3 y fluctuantes; 1RM; volumen/series directas/indirectas/bodyweight/perSide; rachas ambos modos, descansos programados, `validFrom`; fechas; parseo coma/punto. Persistencia: guardar/releer sesión, recuperar sesión, **persistir y releer `RecommendationDecision` (aceptada, modificada, ignorada) y verificar que un recálculo no la sobrescribe**, archivar/eliminar sin alterar pasado, editar plantilla/config sin cambiar historial, migración, export → import sin pérdida ni duplicados. Flujo 2.E de integración con recarga del contenedor. Rendimiento con ~2 años de datos.

## 14. Etapas
0 Entorno/docs/esqueleto · 1 Motor (TDD) + 1RM, volumen, constancia, fechas · 2 Persistencia · 3 **Flujo vertical crítico (puerta de calidad)** · 4 Registro y rutinas completos · 5 Calendario, rachas e Inicio · 6 Análisis · 7 Cierre (export/import, backups, ajustes, accesibilidad, rendimiento, README). No empezar la 4 hasta que la 3 esté verde. MVP = etapas 0–5.

## 15. Qué NO hacer
No recomendar aumentos sin datos que lo justifiquen; no automatizar cambios de carga; no concluir tendencias con una sola sesión; no asumir esfuerzo sin RIR/RPE; no comparar contextos distintos; no obligar a pasar por estadísticas; no empezar extras antes del flujo 2.E; no dar por completo el sistema sin los tests 2.D; no fijar un número ideal de series; no marcar completa una función solo con UI; no integraciones ficticias; no borrar historial; no datos inventados fuera de `#if DEBUG`; no afirmaciones médicas ni 1RM como medición exacta.

## 16. Entrega final
Qué funciona y cómo se verificó (8 casos 2.D, flujo 2.E); qué quedó sin verificar o implementar; cómo compilar/correr/testear; decisiones y limitaciones; próximos pasos (preparados a nivel de arquitectura, no implementados).
