# Progreso

Fuente de verdad del estado del proyecto. Actualizar al cerrar cada etapa.

## Etapa 0 — Entorno, docs y esqueleto · ✅

- Entorno inspeccionado (`docs/ENVIRONMENT.md`): Windows 11 sin Xcode → camino "Linux sin Xcode". Swift 6.4.1 instalado en WSL.
- Docs: `ARCHITECTURE.md`, `DECISIONS.md`, `FORMULAS.md` (borrador), `CLAUDE.md`.
- Repo git inicializado. Paquete `GymCore/` compilando con `swift build`/`swift test` en Linux.

## Etapa 1 — Motor de progresión (TDD) · ✅ (pendiente revisión independiente)

Verificado con `swift test` (Swift 6.4.1, Linux/WSL):

```
$ swift test
✔ Test run with 96 tests in 11 suites passed after 0.014 seconds.
```

| Suite | Cubre |
|---|---|
| 2.D mandatory progression cases (19) | los 8 casos obligatorios, con variantes (sin RIR, RPE, pendientes, pesos disponibles) |
| Determinism and comparability | misma entrada → misma salida; entrada permutada → misma salida; reloj inyectado; cambio de máquina/variante/loadMode; normalización de etiquetas; `ComparabilityLink` transitivo |
| Progression rules | pausa larga y borde de 21 días, atípicas, sesiones no completadas, sesión actual, futuras, calentamiento/drop sets, sesiones consecutivas, series extra, cargas mezcladas, desempate de peso, < repMín, RIR por debajo dentro del rango, caída tras subir carga, caída a menor carga, RIR parcial, config invertida, logs fusionados, mancuernas por lado, peso corporal (reps, lastre, asistencia), duración, tendencia |
| 1RM, Volume, Muscle volume, Personal records, Trend | fórmulas golden, tope de reps, volumen por lado/peso corporal/duración, directas vs indirectas, récords reales vs estimados, clasificación de tendencias |
| Dates, Schedule and streaks, Parsing | DST, zona, medianoche, inicio de semana, fin de mes/año, `validFrom`, modos A y B, objetivo semanal, coma/punto, validaciones |
