# GymProgress

App nativa de gimnasio para iPhone (iOS 17+) cuyo centro es un **asistente de sobrecarga progresiva**: registra lo que hiciste y te dice, con datos reales y un motivo explicable, qué intentar en la próxima sesión. 100 % offline, sin cuentas, sin analytics.

> Nombre de trabajo; se cambia en un solo lugar: `APP_DISPLAY_NAME` en `project.yml`.

## Estado

Ver `docs/PROGRESS.md`. Resumen: el núcleo (motor de progresión, métricas, persistencia y flujo de punta a punta) está **implementado y verificado con tests en Linux**; la app SwiftUI/SwiftData está **escrita pero no compilada** porque el entorno de desarrollo no tenía Xcode.

## Estructura

```
GymCore/                  Swift Package (sin SwiftUI ni SwiftData)
  Sources/GymCore/        dominio, motor de doble progresión, métricas, constancia, fechas
  Sources/GymStore/       repositorio + servicios de aplicación + catálogo + export
  Tests/                  Swift Testing
App/                      app iOS (SwiftUI + SwiftData)
AppTests/                 tests que requieren iOS (SwiftData)
docs/                     SPEC, ARCHITECTURE, DECISIONS, FORMULAS, PROGRESS, ENVIRONMENT
scripts/gen_catalog.py    genera la biblioteca de ejercicios con ids estables
project.yml               proyecto Xcode (XcodeGen)
```

## Correr los tests del núcleo (macOS o Linux)

```bash
cd GymCore
swift test
```

En Windows se usó WSL; ver `docs/ENVIRONMENT.md`.

## Compilar y probar la app (Mac)

Requisitos: macOS 14+, Xcode 16+ con simulador de iPhone, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
xcodebuild -scheme GymProgress -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Después, abrir `GymProgress.xcodeproj` y correr el esquema `GymProgress` en el simulador.

## Principios

- La recomendación aparece arriba de la tabla de series, con motivo y botones **Aceptar / Modificar / Ignorar**; la decisión se guarda siempre.
- El motor es una función pura y determinista (`GymCore/Sources/GymCore/Progression`), con los 8 casos obligatorios de la spec como tests.
- Nunca se inventan datos: sin historial, la app lo dice y deja configurar un objetivo inicial.
- El historial no cambia cuando se edita el catálogo o los criterios (snapshots, archivado lógico).
- Sin afirmaciones médicas; el 1RM es siempre una estimación.
