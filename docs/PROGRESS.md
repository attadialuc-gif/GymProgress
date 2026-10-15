# Progreso

Fuente de verdad del estado del proyecto. Actualizar al cerrar cada etapa.

## Etapa 0 — Entorno, docs y esqueleto · ✅

- Entorno inspeccionado (`docs/ENVIRONMENT.md`): Windows 11 sin Xcode → camino "Linux sin Xcode". Swift 6.4.1 instalado en WSL.
- Docs: `ARCHITECTURE.md`, `DECISIONS.md`, `FORMULAS.md` (borrador), `CLAUDE.md`.
- Repo git inicializado. Paquete `GymCore/` compilando con `swift build`/`swift test` en Linux.

## Etapa 1 — Motor de progresión (TDD) · 🟡 en curso

- ✅ 8 casos obligatorios 2.D (19 tests) en verde:
  ```
  $ swift test
  ✔ Suite "2.D mandatory progression cases" passed
  ✔ Test run with 19 tests in 1 suite passed
  ```
- Pendiente: determinismo, no comparabilidad, casos extra del motor, 1RM, volumen, constancia, fechas, parseo.
