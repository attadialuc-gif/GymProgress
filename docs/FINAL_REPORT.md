# Informe final (sección 16)

Fecha: 2026-10-15. Entorno: Windows 11 + WSL (Kali), Swift 6.4.1 para Linux. **Sin Mac ni Xcode.**

## 1. Qué funciona y cómo se verificó

Comando (en `GymCore/`, Linux):

```
$ swift test
✔ Test run with 103 tests in 11 suites passed      GymCoreTests
✔ Test run with 40 tests in 6 suites passed        GymStoreTests
2-year dataset: 5 recommendations + history + digests in 0.26 seconds
```

**Sección 2.D, los 8 casos obligatorios: todos en verde** (`ProgressionMandatoryCasesTests`, 19 tests con variantes):

| # | Caso | Estado |
|---|---|---|
| 1 | Rango superior no alcanzado → mantener 60 kg, +1 rep (11, 10, 9) | ✅ |
| 2 | Tope alcanzado con RIR → 62,5 kg × 8, confianza alta; sin RIR → condicionada ("Podrías subir a 62,5 kg si…") | ✅ |
| 3 | Reps cumplidas con RIR por debajo → no sube, explica el esfuerzo | ✅ |
| 4 | Rendimiento inferior → mantener, historial, sin reducción; 2 sesiones seguidas bajo el mínimo → reevaluar | ✅ |
| 5 | Sin historial → "Todavía no hay datos suficientes", sin números; con objetivo inicial → "objetivo inicial" | ✅ |
| 6 | Incrementos 2,5 / 5 / lista [60, 62, 64] / sin peso mayor → aviso; config no altera el pasado | ✅ |
| 7 | Series incompletas / pendientes → no sube; pendiente ≠ 0; sin series completadas no es comparable | ✅ |
| 8 | Modificación manual persistida, sobrevive a recargar, no la pisa un recálculo, la siguiente usa lo realizado | ✅ motor + persistencia (`PersistenceTests.case8…`) |

Además: determinismo (misma entrada, entrada permutada, reloj inyectado) y no comparabilidad (máquina, variante, modo de carga, `ComparabilityLink` transitivo) en verde.

**Sección 2.E, flujo de punta a punta: en verde** (`EndToEndFlowTests.fullFlow`): crear rutina → ejercicio del catálogo → objetivo → abrir (tarjeta) → aceptar → registrar series → finalizar → historial → recomendación siguiente (52,5 kg × 8), **recargando el almacenamiento desde disco entre cada paso**.

También verificado: persistencia y recuperación de sesión, decisiones aceptar/modificar/ignorar, historial inmutable, archivado vs borrado, export/import sin duplicados ni pisar datos, catálogo de 98 ejercicios, superseries, calendario con `validFrom`, rachas A/B, estadísticas por período y músculo, récords y objetivos, fechas (DST, zona, medianoche, inicio de semana, fin de mes/año), parseo con coma o punto, rendimiento con ~2 años de datos.

**Revisiones independientes** (subagentes sin contexto): etapa 1 (3 mayores, corregidos) y etapas 2–3 (1 crítico, 5 mayores, 12 menores, corregidos); la re-revisión aprobó la puerta de calidad de la etapa 3.

## 2. Sin verificar o sin implementar

- **App iOS (SwiftUI, SwiftData, Swift Charts, notificaciones): escrita y completa para las etapas 0–7, pero NO compilada ni ejecutada.** Solo se verificó la sintaxis (`swiftc -parse`, 26 archivos sin errores). Puede haber errores de tipos/API que solo aparezcan con Xcode.
- `AppTests/SwiftDataRepositoryTests.swift` (caso 8, recuperación, export/import, flujo 2.E sobre SwiftData): escritos, **no ejecutados**.
- Test de UI en simulador: no escrito (no hay simulador disponible).
- Datos de demostración `#if DEBUG`: no implementados (el generador de 2 años existe solo en los tests).
- Accesibilidad: etiquetas VoiceOver, Dynamic Type y textos de ayuda incluidos, pero **no auditados en dispositivo**.
- Ícono de la app: el catálogo de assets tiene el slot vacío.

## 3. Compilar, correr y testear

Ver `README.md`. Resumen: `cd GymCore && swift test` (Linux/macOS); en Mac: `brew install xcodegen && xcodegen generate && xcodebuild -scheme GymProgress -destination 'platform=iOS Simulator,name=iPhone 16' test`.

## 4. Decisiones relevantes y limitaciones

Ver `docs/DECISIONS.md` (D-001…D-039). Las más importantes:
- Capa `GymStore` independiente de la persistencia para verificar en Linux casi toda la lógica; SwiftData implementa el mismo protocolo (D-003).
- Orden de reglas: la caída de rendimiento se evalúa antes de "sumar reps" (caso 2.D-4); RIR faltante ⇒ condicionada siempre (2.B manda sobre 8.2) (D-010, D-011).
- Solo se compara rendimiento al mismo peso; cambiar de carga nunca es "caída" (D-015).
- Tendencia por reps a carga constante o 1RM estimado con tope (D-021).
- Importar solo agrega; nunca pisa ni borra datos locales (D-033).
- Limitación: el JSON del repositorio de tests reescribe el archivo completo en cada cambio (solo tests); la app usa SwiftData.

## 5. Próximos pasos recomendados (preparados a nivel de arquitectura, **no implementados**)

1. Compilar en un Mac, corregir lo que marque el compilador, correr `GymProgressTests` y probar el flujo en simulador y en un iPhone real.
2. Test de UI del flujo 2.E en simulador.
3. Ícono y pantalla de lanzamiento.
4. Datos demo `#if DEBUG`.
5. Widgets (próximo entrenamiento + recomendación), Apple Health (peso corporal, entrenamientos), sincronización/iCloud, medidas corporales (`BodyWeightEntry`), recordatorios, informes PDF. Todo se apoya en `GymStore`/`StatsService` sin tocar el motor.
