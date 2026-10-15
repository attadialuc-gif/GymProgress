# Arquitectura de GymProgress

App nativa para iPhone (iOS 17+, SwiftUI + SwiftData), 100 % offline. El producto es un **asistente de sobrecarga progresiva**: registrar lo hecho (datos) y recomendar qué hacer la próxima sesión (motor).

## Capas

Las dependencias apuntan hacia el núcleo:

```
App (SwiftUI, @Observable)          ← no verificable sin Xcode
  Features/   vistas + view models por feature
  Services/   timer de descanso, notificaciones, hápticos, exportación
  Persistence/ @Model SwiftData + SwiftDataGymRepository (implementa GymRepository)
  DesignSystem/
        │
        ▼
GymStore (Swift puro, verificado con swift test)
  Records       entidades persistibles como structs (sesión, ExerciseLog, SetLog, decisión…)
  GymRepository protocolo que oculta la persistencia
  InMemory/File repos   implementación en memoria y en archivo JSON (tests y reload)
  WorkoutService        flujo de sesión: abrir ejercicio → recomendación congelada → decisión → series → guardar
  RoutineService, HistoryService, CatalogSeeder, Export DTOs
        │
        ▼
GymCore (Swift puro, sin SwiftUI/SwiftData, verificado con swift test)
  Models/       valores inmutables, Sendable, Codable
  Progression/  motor de doble progresión (ProgressionStrategy) ← núcleo del producto
  Metrics/      1RM, volumen, series directas/indirectas, récords, tendencias
  Consistency/  calendario planificado, sesiones válidas, rachas (modo A y B), fechas
  Support/      aritmética de cargas, parseo de pesos (coma/punto), formateo es-AR
```

### Por qué existe `GymStore`

La spec pide repositorios detrás de protocolos. Llevar también los **servicios de aplicación** a un target Swift puro permite verificar en Linux casi todo el comportamiento crítico (recomendación congelada, decisiones aceptar/modificar/ignorar que el motor nunca pisa, recuperación de sesión, historial inmutable, flujo de punta a punta con recarga desde disco). En iOS, `SwiftDataGymRepository` implementa el mismo protocolo, de modo que la app usa exactamente los mismos servicios. Ver `DECISIONS.md` D-003.

## Flujo crítico (sección 2.E)

```
RoutineService.createRoutine → addExercise(config/objetivo)
WorkoutService.startSession(routine)          crea WorkoutSession + ExerciseLogs (snapshots)
WorkoutService.openExercise(log)              calcula Recommendation con historial PREVIO y la congela en el log
WorkoutService.decide(log, accept|modify|ignore)  persiste RecommendationDecision (fuente de verdad)
WorkoutService.updateSet / completeSet        guardado incremental
WorkoutService.finishSession                  estado completed
HistoryService.performances(exercise)         historial
WorkoutService.previewRecommendation(exercise) recomendación para la próxima sesión
```

## Reglas de diseño

- Cálculos de progresión y métricas **solo** en `GymCore`, funciones puras y deterministas: el "ahora", el calendario y el locale se inyectan; el historial se ordena internamente.
- Las vistas no tienen lógica de negocio: la tarjeta de recomendación presenta un `Recommendation`.
- El historial es inmutable respecto del catálogo: cada `ExerciseLog` guarda snapshot del ejercicio y de la `ProgressionConfig` vigente; rutinas y ejercicios se archivan, no se borran si tienen historial.
- `RecommendationDecision` es la fuente de verdad de lo que eligió el usuario; recalcular nunca la sobrescribe.
- Sin red, sin analytics, sin dependencias de terceros en runtime.

## Modelo de datos

Ver la sección 7 de la spec; los tipos concretos están en `GymCore/Sources/GymStore/Records.swift` (structs) y `App/Persistence/SchemaV1.swift` (@Model). Diferencias de catálogo vs historial:

| Catálogo / plantillas (editables) | Historial (inmutable salvo edición explícita del usuario) |
|---|---|
| `Exercise`, `ProgressionConfig`, `RoutineTemplate`, `RoutineExercise`, `ScheduleEntry` (append-only con `validFrom`) | `WorkoutSession`, `ExerciseLog` (snapshot + contexto + recomendación congelada), `SetLog`, `RecommendationDecision`, `ComparabilityLink`, `PersonalRecord` (derivado) |

## Etapas

| # | Etapa | Estado → ver `PROGRESS.md` |
|---|---|---|
| 0 | Entorno, docs y esqueleto | |
| 1 | Motor de progresión en GymCore (TDD) + métricas, constancia, fechas | |
| 2 | Persistencia (GymStore verificado; SwiftData escrito, no verificable aquí) | |
| 3 | Flujo vertical crítico (puerta de calidad) | |
| 4 | Registro y rutinas completos | |
| 5 | Calendario, rachas e Inicio | |
| 6 | Análisis | |
| 7 | Cierre | |
