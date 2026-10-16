# GymProgress — memoria del proyecto

App nativa iPhone (iOS 17+) de gimnasio cuyo producto central es un **asistente de sobrecarga progresiva**. Offline, sin red, sin terceros.

## Stack
- Swift 6 (language mode 6), SwiftUI + Observation, SwiftData (VersionedSchema + plan de migración), Swift Charts.
- `GymCore/` Swift Package (sin SwiftUI/SwiftData): targets `GymCore` (dominio, motor, métricas) y `GymStore` (repositorio + servicios de aplicación + store JSON). Tests con Swift Testing.
- `App/` target iOS (generado con XcodeGen desde `project.yml`).

## Estructura
```
GymCore/Sources/GymCore/{Models,Progression,Metrics,Consistency,Support}
GymCore/Sources/GymStore/        records, GymRepository, servicios, export
GymCore/Tests/{GymCoreTests,GymStoreTests}
App/{Persistence,Features,Services,DesignSystem,Resources}
AppTests/                        tests SwiftData/UI (solo en Mac)
docs/                            ENVIRONMENT, ARCHITECTURE, DECISIONS, FORMULAS, PROGRESS
```

## Comandos
- Tests del paquete (Linux/WSL o Mac): `cd GymCore && swift test`
  - En esta PC (Windows): ver `docs/ENVIRONMENT.md` (WSL kali, `PATH` y `LD_LIBRARY_PATH`).
- App (solo Mac): `xcodegen generate && xcodebuild -scheme GymProgress -destination 'platform=iOS Simulator,name=iPhone 16' test`
- git: en esta PC, ejecutar git desde WSL (Windows bloquea escrituras de bash/PowerShell en Documents).

## Convenciones
- UI y docs en español (es-AR); código, identificadores, tests y commits en inglés.
- Números y fechas con `FormatStyle`/`Locale`, nunca strings armados a mano. Pesos aceptan coma o punto (`WeightParser`), se guardan en kg normalizados a 1 g (`LoadMath`).
- Lógica de negocio solo en `GymCore`/`GymStore`; las vistas presentan.
- Funciones de cálculo puras y deterministas: "ahora", calendario y locale se inyectan.
- Toda decisión no trivial → `docs/DECISIONS.md`. Al cerrar etapa → `docs/PROGRESS.md` + commit.
- Nada es "terminado" sin ejecutarlo/testearlo. Nunca afirmar que compila o pasa sin correr el comando.

## Port Android/Windows (`crossplatform/`, rama `feat/crossplatform`)
- Flutter + Dart (D-100). `crossplatform/gym_core` (dominio y motor, Dart puro), `crossplatform/gym_store` (SQLite, repos, servicios, import/export), `crossplatform/app` (UI Flutter, sin lógica de negocio).
- Fidelidad (D-101): `GymCore/Sources/FixtureExporter` corre la lógica Swift y escribe `crossplatform/fixtures/*.json`; los tests Dart deben coincidir con esos fixtures. Una diferencia es un bug del port salvo que se demuestre un bug en Swift (en ese caso se corrigen ambos, con test y entrada en DECISIONS).
- Regenerar fixtures (WSL): `cd GymCore && swift run -c debug FixtureExporter export ../crossplatform/fixtures`.
- Tests Dart (WSL, Flutter en `~/flutter/bin`): `cd crossplatform/gym_core && dart test`; ídem `gym_store`; app: `flutter test`.
- CI: `test.yml` (cada push), `build-android.yml`, `build-windows.yml`. La app de iOS y `build-ios.yml` no se modifican.
- Firma Android: keystore fuera del repo, solo como secretos de GitHub. Nunca versionar `*.jks`, `key.properties`, contraseñas ni rutas personales.
- Estado: etapas A–G completas (ver `docs/PROGRESS.md`). Tests: `gym_core` 113, `gym_store` 62, app 28 + integración 2.E en Windows y emulador Android (CI). Entregables en `dist/` (no versionado): `GymProgress.apk`, `GymProgress-Setup.exe`, `GymProgress-windows.zip`. Guías: `docs/INSTALAR_ANDROID.md`, `docs/INSTALAR_WINDOWS.md`; diferencias: `docs/PARIDAD.md`.
- Escritura en Windows: Controlled Folder Access bloquea Write/Edit en Documents → escribir en el scratchpad y copiar desde WSL, o editar con python en WSL.
- Revisión de privacidad antes de cada push (patrón en el script de commit): sin email personal, rutas de la PC, contraseñas literales ni claves.

## Reglas permanentes (resumen de la sección 2 de la spec — prioridad máxima)
1. Prioridades: integridad de datos > sistema de sobrecarga progresiva > velocidad de registro > resto.
2. Al abrir un ejercicio en sesión, la **tarjeta de recomendación** va arriba de la tabla de series: última sesión comparable (peso y reps por serie), objetivo de hoy (series, rango, RIR), peso/reps recomendados, motivo (1–2 líneas), botones **Aceptar / Modificar / Ignorar**. La decisión se persiste siempre (`RecommendationDecision`) y nunca la pisa un recálculo.
3. Motor de doble progresión puro en `GymCore` (`ProgressionStrategy`): no subir sin datos que lo justifiquen; sin RIR/RPE → recomendación **condicionada**; nunca reducir/aumentar automáticamente por una sola sesión; no declarar estancamiento con < 3 sesiones o con fluctuación; no comparar máquinas/variantes distintas sin `ComparabilityLink`.
4. Nunca inventar sesiones, pesos ni récords. Sin historial → "Todavía no hay datos suficientes" + objetivo inicial configurable.
5. Determinismo: sin aleatoriedad, sin leer reloj, orden interno estable. Tests lo verifican.
6. Los 8 casos de la sección 2.D + determinismo + no comparabilidad deben estar en verde. Flujo de punta a punta (crear rutina → … → recomendación siguiente) con persistencia y recarga antes de cualquier extra.
7. Historial inmutable: snapshots en `ExerciseLog`; archivar en lugar de borrar; cambiar config no reescribe el pasado.
8. Datos demo solo bajo `#if DEBUG`. Sin afirmaciones médicas; el 1RM siempre es "estimado".
