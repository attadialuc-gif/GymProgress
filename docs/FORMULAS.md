# Fórmulas y reglas de cálculo

Todo lo de este documento está implementado en `GymCore` (funciones puras) y cubierto por tests en `GymCore/Tests/GymCoreTests`. Cargas en kg con resolución de 1 g (`LoadMath`): las comparaciones usan claves enteras en gramos, nunca igualdad de `Double`.

## 8.1 Definiciones base

| Término | Definición | Código |
|---|---|---|
| Serie efectiva | `kind ∈ {working, dropSet}`, `status == completed`, valores válidos: `weightReps` peso ≥ 0 y reps ≥ 1; `bodyweightReps` reps ≥ 1; `duration` segundos ≥ 1. Las pendientes nunca valen cero. | `PerformedSet.isEffective` |
| Serie de progresión | Igual que efectiva pero solo `kind == working` (los drop sets no alimentan el motor). | `PerformedSet.feedsProgression` |
| Contexto de comparabilidad | `(exerciseId, variantLabel, equipmentLabel, loadMode)`; etiquetas normalizadas (sin espacios extra, sin mayúsculas ni tildes, vacía = nil). Comparables si son iguales o hay un `ComparabilityLink` (simétrico y transitivo). | `ComparabilityContext`, `ComparabilityResolver` |
| Sesión comparable | sesión `completed`, no atípica (sesión ni ejercicio), no es la sesión actual, no futura, misma medición, contexto equivalente, ≥ 1 serie de progresión. Varios logs del mismo ejercicio en una sesión se fusionan. Orden: más reciente primero (desempate estable por ids). | `HistoryAnalyzer.comparable` |
| Peso de trabajo | Peso más frecuente entre las series de progresión; empate → el mayor. En peso corporal: carga neta = adicional − asistencia. | `HistoryAnalyzer.workingLoad` |
| RIR efectivo | RIR registrado, o 10 − RPE si solo hay RPE. | `PerformedSet.effectiveRIR` |

## 8.2 Doble progresión

Entradas: `ProgressionConfig` saneada, historial (cualquiera; el motor filtra y ordena), vínculos de comparabilidad, `now`, calendario y locale inyectados. Sin aleatoriedad ni reloj.

Orden de evaluación (ver D-010):

1. **Sin historial comparable** → `needsInitialTarget`. Con peso inicial configurado: `targetWeight` = peso inicial, reps = repMín, motivo "objetivo inicial". Si hay historial en otro contexto: motivo `noComparableHistoryInContext` y se adjunta como `nonEquivalentReference`.
2. **Pausa larga**: días calendario desde la última sesión comparable > `reassessAfterDays` (21) → `reassess`, peso de referencia = último, reps = repMín.
3. **Series incompletas**: series evaluadas (a peso de trabajo, hasta `targetSets`) < `targetSets` → `maintain`; objetivo = reps hechas (acotadas al rango) + repMín en las faltantes.
4. **Tope alcanzado** (todas las evaluadas ≥ repMáx):
   - 5\. algún RIR registrado < objetivo → `maintain` (`effortAboveTarget`).
   - racha de sesiones consecutivas al tope con el mismo peso < `requiredConsecutiveSessions` → `maintain` (`topOfRangeNeedsConfirmation`).
   - siguiente carga: con `availableWeights` → el menor disponible estrictamente mayor; si no → actual + `increment`. Sin carga mayor disponible → `maintain` con aviso.
   - `increaseWeight`, reps objetivo = repMín. Confianza `high` si todas las series tienen RIR (≥ objetivo si existe); si falta alguno → `conditional` con condiciones explícitas.
5. **7b** algunas series < repMín en la última **y** en la anterior comparable al mismo peso → `reassess` (la reducción la decide el usuario).
6. **7 Rendimiento inferior** (D-015) → `maintain`, objetivo = recuperar las reps de la sesión anterior.
7. Series < repMín solo en la última → `maintain`, objetivo = llevar esas series a repMín.
8. **6 Dentro del rango**: algún RIR registrado < objetivo → `maintain` (`repsHeldByEffort`); si no → `increaseReps`: +1 rep (o +`secondsIncrement` s) en cada serie bajo el máximo, acotado al máximo. Sin RIR → `conditional`.

Variantes: peso corporal (D-018), duración (D-019), `perSide` usa la lista de pesos disponibles (mancuernas) y el peso guardado es por lado.

Salida: `Recommendation` (acción, motivo, confianza, peso, reps/segundos por serie, objetivo de la sesión, texto, condiciones, notas, contexto, última sesión, evidencia ≤ 5, referencia no equivalente, tendencia, fecha).

## Tendencia (regla 8)

Ver D-021. Serie de valores cronológica (máx. 6 últimas sesiones comparables):

- `n < 3` → sin conclusión.
- pendiente relativa = pendiente de mínimos cuadrados / media.
- ≥ +1 % por sesión → progresando.
- ≤ −1 % por sesión y el último valor es un nuevo mínimo → descenso.
- (máx − mín) / media ≤ 3 % → posible estancamiento.
- resto → estable (fluctúa; no se declara estancamiento).

## 8.3 1RM estimado

- Epley: `w × (1 + r/30)`; Brzycki: `w × 36 / (37 − r)` (r < 37). Con r = 1 ambas devuelven `w`.
- Se excluyen series con más de `maxReps` (10 por defecto) y las marcadas por el usuario. Siempre rotulado "estimado".
