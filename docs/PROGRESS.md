# Progreso

Fuente de verdad del estado del proyecto. Actualizar al cerrar cada etapa.

**Leyenda:** ✅ verificado (ejecutado/testeado) · 📝 escrito, **no verificado** (requiere Mac con Xcode) · ⏳ pendiente.

## Etapa 0 — Entorno, docs y esqueleto · ✅

- Entorno inspeccionado (`docs/ENVIRONMENT.md`): Windows 11 sin Xcode → camino "Linux sin Xcode". Swift 6.4.1 instalado en WSL (firma GPG verificada).
- Docs: `SPEC.md` (copia de la especificación), `ARCHITECTURE.md`, `DECISIONS.md`, `FORMULAS.md`, `CLAUDE.md`, `project.yml` (XcodeGen).
- Repo git inicializado.

## Etapa 1 — Motor de progresión (TDD) · ✅ revisada

- Motor de doble progresión, comparabilidad, 1RM, volumen, músculos, récords, tendencias, calendario, rachas, fechas, parseo.
- Revisión independiente (subagente sin contexto): 3 hallazgos mayores y varios menores, **todos corregidos** con tests de regresión (D-015, D-015b, D-021, D-024…D-028).

## Etapa 2 — Persistencia · ✅ (GymStore) / 📝 (SwiftData)

- ✅ `GymStore`: records, protocolo `GymRepository`, `JSONGymRepository` (archivo, escritura atómica en cada cambio, índices), `WorkoutService` (recomendación congelada, decisiones aceptar/modificar/ignorar, completar en un toque, recuperación, cambios solo de la sesión), `RoutineService`, `ExerciseCatalogService` (catálogo de 98 ejercicios con UUID estables), plantillas, `ExportService` (JSON con `schemaVersion`, import validado sin duplicados, CSV).
- 📝 SwiftData: `App/Persistence/SchemaV1.swift` (`VersionedSchema` + `GymMigrationPlan`) y `SwiftDataGymRepository` (mismo contrato). Tests en `AppTests/SwiftDataRepositoryTests.swift` (caso 8, recuperación, export/import, apertura con el plan de migración) — **no ejecutados**.

## Etapa 3 — Flujo vertical crítico · ✅ puerta de calidad aprobada (lógica) / 📝 UI

- Revisión independiente de etapas 2–3: 1 crítico (import pisaba historial más nuevo), 5 mayores y 12 menores → **todos corregidos** con tests de regresión (`ReviewRegressionTests`). Re-revisión: **aprobada** ("Stage 3 passes the gate"); sus 4 observaciones no bloqueantes también se corrigieron (import no resucita lo borrado de una sesión local, guardado al pasar a segundo plano, carrera del temporizador, aviso de parseo).
- Tests actuales: 103 (GymCore) + 28 (GymStore) en verde; 21 archivos de la app sin errores de sintaxis.

- ✅ Test de integración del flujo 2.E (`EndToEndFlowTests.fullFlow`): crear rutina → elegir ejercicio del catálogo → objetivo (3 × 8–12, RIR 2, inicial 50 kg) → abrir ejercicio (tarjeta) → aceptar → registrar series → finalizar → historial → recomendación siguiente (52,5 kg × 8, confianza alta), **recargando el store desde disco entre cada paso**.
- ✅ Caso 2.D-8 completo con persistencia (`PersistenceTests.case8_modifiedDecisionLifecycle`).
- ✅ Rendimiento: 2 años sintéticos (416 sesiones × 6 ejercicios × 4 series): 5 recomendaciones + historial + resúmenes ≈ 0,15 s (debug).
- 📝 UI SwiftUI mínima pero completa del flujo: 5 pestañas, rutinas (crear, plantillas, duplicar, archivar, reordenar, editor de criterios por ejercicio), biblioteca + ejercicios propios, sesión (tiempo sin pausas, pausar/finalizar/descartar con confirmación, agregar/quitar/reordenar solo hoy, atípica, notas), pantalla de ejercicio con **tarjeta de recomendación arriba** (última sesión, objetivo, recomendado, motivo, condiciones, Aceptar/Modificar/Ignorar, copiar cargas, objetivo inicial), tabla de series (coma/punto, RIR en un toque, completar en un toque con háptico y temporizador por timestamp + notificación local), cambio de máquina/variante y "tratar como equivalente", historial por ejercicio con recomendación siguiente, ajustes básicos y exportación. Sintaxis verificada con `swiftc -parse` (19 archivos, sin errores); **no compilada ni probada en simulador**.

### Comandos y resultados

```
$ cd GymCore && swift test        # Swift 6.4.1, Linux (WSL)
✔ Test run with 103 tests in 11 suites passed      (GymCoreTests)
✔ Test run with 19 tests in 2 suites passed        (GymStoreTests)
2-year dataset: 5 recommendations + history + digests in 0.147 seconds

$ swiftc -parse App/**/*.swift AppTests/*.swift
(sin errores)
```

## Etapa 4 — Registro y rutinas completos · ✅ lógica / 📝 UI

- ✅ Superseries en sesión: el log copia el grupo de la rutina; `WorkoutService.restAdvice` alterna ejercicios del grupo sin descanso y descansa al cerrar la ronda (test `Stage4Tests`).
- ✅ Historial de entrenamientos (`HistoryService.completedSessionSummaries`: solo sesiones completadas, más nuevas primero, series efectivas, volumen externo, duración sin pausas).
- ✅ Compatibilidad de esquema: logs guardados sin campos nuevos opcionales siguen decodificando.
- 📝 UI: biblioteca (buscar, filtrar por músculo, archivados, crear propios), detalle de ejercicio (criterios de progresión predeterminados, archivar, eliminar sin historial con confirmación), lista y detalle de entrenamientos realizados (orden real, decisiones), insignia y botón "seguí con…" en superseries.

```
$ swift test
✔ Test run with 103 tests in 11 suites passed   (GymCoreTests)
✔ Test run with 31 tests in 4 suites passed     (GymStoreTests)
$ swiftc -parse (23 archivos de la app)          sin errores
```

## Etapa 5 — Calendario, rachas e Inicio · ✅ lógica / 📝 UI

- ✅ `ConsistencyService`: plan semanal append-only con `validFrom` (`setWeeklyPlan`), vista mensual/semanal con hecho/planificado/omitido/descanso, resumen semanal con objetivo (sin empujar a entrenar de más), rachas modo A y B con su definición en texto. Tests en `Stage5And6Tests`.
- 📝 UI: calendario mensual/semanal con leyenda accesible y editor de plan semanal; Inicio con próximo entrenamiento y sus recomendaciones, semana/objetivo, racha (con definición), volumen semanal vs anterior + gráfico de 8 semanas, récords recientes, última sesión.

## Etapa 6 — Análisis · ✅ lógica / 📝 UI

- ✅ `StatsService`: períodos (semana, 30 días, mes, 90 días, año, 12 meses, personalizado) con período anterior equivalente; totales y comparación (sesiones válidas, días, series efectivas, volumen externo) con filtro por rutina; serie por ejercicio (peso de trabajo, reps, 1RM estimado con tope, volumen, sesiones atípicas marcadas, contexto); volumen por músculo directo/indirecto y evolución semanal; récords recientes (solo los superados); objetivos con progreso y logro automático.
- 📝 UI: Progreso con filtros de período y rutina, comparación, gráficos Swift Charts por ejercicio y métrica, series por músculo (directas e indirectas separadas), récords (real vs estimado) y objetivos; cada indicador con ayuda.

```
$ swift test
✔ Test run with 103 tests in 11 suites passed   (GymCoreTests)
✔ Test run with 40 tests in 6 suites passed     (GymStoreTests)
$ swiftc -parse (26 archivos de la app)          sin errores
```

## Etapa 7 — Cierre · ✅ lógica / 📝 UI

- ✅ Export JSON completo con `schemaVersion` + chequeo de integridad, import validado que solo agrega (copias de seguridad/restauración), CSV de series.
- 📝 Ajustes completos (unidades, inicio de semana, descanso, tema, pantalla, avisos, objetivo semanal, modo de racha y separación, mínimo de series, fórmula y tope de 1RM, factor de indirectas, peso corporal), importar con selector de archivos y resumen, compartir JSON/CSV.
- Informe final: `docs/FINAL_REPORT.md`.

```
$ swift test
✔ Test run with 103 tests in 11 suites passed   (GymCoreTests)
✔ Test run with 40 tests in 6 suites passed     (GymStoreTests)
$ swiftc -parse (26 archivos de la app)          sin errores
```

## Revisión independiente de etapas 4–7 · ✅ corregida

- 0 críticos, 7 mayores, 12 menores. Todos corregidos; los confirmados con tests de regresión (`Stage4To7ReviewTests`, 11 tests): plan con fecha pasada, plan futuro guardado antes, próximo entrenamiento, récords/gráficos por contexto, comparación a la fecha, récords recientes sin duplicados, calentamiento en superserie, resumen de importación, fecha de objetivo logrado, CSV, objetivos por músculo.
- UI: peso corporal se guarda al salir del campo, objetivos de series por músculo, frecuencia por semana, filtro de rutina en músculos y ejercicios, etiquetas según medición, validación de criterios del ejercicio, objetivo de reps exige peso, superserie reemplaza pantalla, zona horaria actual.

```
$ swift test
✔ Test run with 103 tests in 11 suites passed   (GymCoreTests)
✔ Test run with 51 tests in 7 suites passed     (GymStoreTests)
$ swiftc -parse (26 archivos de la app)          sin errores
```

## Compilación iOS en CI y .ipa · ✅

- Repo: https://github.com/attadialuc-gif/GymProgress (público, historial sin datos personales).
- Run verde: https://github.com/attadialuc-gif/GymProgress/actions/runs/38781147138 (Xcode 26.6, Swift 6.3.3).
  - `packages`: 154 tests en 18 suites, en macOS.
  - `build-ipa`: `BUILD SUCCEEDED`, `GymKit.framework` embebido (verificado con `otool -L`), `GymProgress.ipa` 1,7 MB.
  - `app-tests`: 6 tests (7 casos) de la capa de app sobre SwiftData en simulador iPhone 17 Pro: caso 2.D-8 con recarga, recuperación, export/import, migración v1, flujo 2.E.
- `.ipa` sin firmar en `dist/GymProgress.ipa` (no se versiona); instalación: `docs/INSTALAR_EN_IPHONE.md`.
- Sin verificar: instalación y uso en un iPhone real; la UI no tiene tests automatizados de interfaz.

## Port a Android y Windows (`crossplatform/`, rama `feat/crossplatform`)

Flutter + Dart (D-100). La app de iOS no se toca; la fuente de verdad es el código Swift y sus tests, volcados a fixtures JSON (D-101).

### Etapa A — Decisión, andamiaje, exportador de fixtures, CI · ✅

- `GymCore/Sources/FixtureExporter` (target ejecutable nuevo, sin cambiar lógica Swift): genera `crossplatform/fixtures/` — 72 casos del motor (8 casos 2.D, determinismo, no comparabilidad, reglas), helpers, métricas, calendario/constancia, parseo/formato, 42 escenarios de store (807 operaciones) y un export de Swift.
- Andamiaje: `crossplatform/gym_core` (Dart puro), `crossplatform/gym_store` (SQLite vía `sqlite3`, D-102), `crossplatform/app` (Flutter, plataformas android y windows).
- CI `.github/workflows/test.yml`: `dart test` de los paquetes + `flutter test` de la app en cada push; job `fixtures` que regenera los fixtures con Swift en Linux y verifica que coincidan con los versionados.

```
$ swift run FixtureExporter export crossplatform/fixtures      (WSL, Swift 6.4.1)
engine 72 · scenarios 42 / 807 ops · verify-import export_from_swift.json: OK (128 insertados, reimport 0)
$ dart test   (gym_store, smoke SQLite)                         +1: All tests passed!
```

### Etapa B — `gym_core` en Dart · ✅ revisada

- Port de modelos, motor de doble progresión, textos, historial comparable, tendencia, 1RM, volumen, músculos, récords, calendario (zona IANA con paquete `timezone`), agenda con `validFrom`, rachas y parseo/formato.
- Verde contra los fixtures de Swift: los 8 casos 2.D, determinismo (5 órdenes de entrada + orden de series), no comparabilidad (máquina, variante, modo de carga, vínculos), reglas, métricas, 176 casos de calendario (incluye DST a medianoche: Santiago, Beirut, La Habana) y parseo/formato.
- Revisión independiente (subagente) contra la sección 2 y el código Swift: 2 mayores (UUID en minúsculas, colisión de `sortKey` entre contextos distintos) y 6 menores (plegado Unicode, espacios, `DateTime` local vs UTC, signo de cero, precisión, locales). Todas corregidas con tests o registradas (D-103, D-104); verificación posterior del revisor: cerradas.

```
$ dart analyze      No issues found!
$ dart test         +113: All tests passed!   (WSL, Dart 3.13.5)
```

## Próximos pasos

- En un Mac: `xcodegen generate`, compilar, corregir lo que marque el compilador, correr `GymProgressTests` y probar el flujo en simulador y en un iPhone.
- Pendientes listados en `docs/FINAL_REPORT.md` §2 y §5.
