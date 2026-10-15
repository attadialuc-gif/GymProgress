# Registro de decisiones

Formato: decisión · alternativas · motivo. Las decisiones del motor (D-010+) explican cómo se resolvieron ambigüedades entre las secciones 2 y 8 (manda la sección 2).

## Entorno y estructura

**D-001 · Ubicación del proyecto.** Subcarpeta `GymProgress/` dentro de la carpeta abierta (un proyecto de trading bot), con repo git propio. · Alternativa: carpeta hermana fuera del bot. · Elegido por el usuario.

**D-002 · Toolchain.** Swift 6.4.1 oficial (Debian 13) en WSL `kali-linux`, sin sudo, + `libxml2.so.2` de Debian en `~/swift/extra-libs`. · Alternativas: Swift para Windows (varios GB + VS Build Tools), no instalar nada. · Elegido por el usuario; aísla el toolchain de Windows.

**D-003 · Capa `GymStore` independiente de la persistencia.** Servicios de aplicación (`WorkoutService`, `RoutineService`, …) y el protocolo `GymRepository` viven en un target Swift puro; SwiftData es una implementación del protocolo en la app. · Alternativa: servicios dentro del target iOS, acoplados a `ModelContext`. · Motivo: en este entorno no hay Xcode; así se verifica con `swift test` la lógica crítica de la sección 2 (recomendación congelada, decisiones, recuperación, recarga) y la app usa exactamente el mismo código.

**D-004 · Swift Testing** (`import Testing`) en lugar de XCTest para los tests del paquete. · Motivo: argumentos parametrizados para los casos golden; disponible en Xcode 16+ y en el toolchain de Linux.

**D-005 · Swift 6 language mode** (concurrencia estricta). Servicios y repositorios son `@MainActor`; los modelos de dominio son `Sendable`.

**D-006 · XcodeGen (`project.yml`)** para generar el `.xcodeproj` en el Mac, en lugar de versionar un `.pbxproj` escrito a mano.

## Motor de progresión

**D-010 · Orden efectivo de reglas.** 1 sin historial → 2 pausa larga → 3 series incompletas → (tope alcanzado: 5 esfuerzo / 4 confirmación, peso disponible, subir) → 7b series < repMín en 2 sesiones seguidas (`reassess`) → 7 rendimiento inferior (`maintain`) → series < repMín en una sola sesión (`maintain`) → 6 subir repeticiones. · La sección 8.2 lista la regla 6 antes de la 7, pero el caso obligatorio 2.D-4 (12, 11, 10 → 10, 9, 8) exige "mantener" y no "sumar repeticiones"; manda la sección 2.

**D-011 · RIR no registrado ⇒ recomendación condicionada**, aunque no haya RIR objetivo configurado. · 8.2 solo lo exige "si hay RIR objetivo"; 2.B lo exige siempre que falte información de esfuerzo. Manda 2.B. Con RIR registrado en todas las series y sin objetivo, la confianza es alta.

**D-012 · Sin historial + peso inicial configurado** ⇒ `action = needsInitialTarget`, `reason = initialTarget`, `targetWeight = peso inicial`. Sin peso inicial ⇒ `targetWeight = nil` y el texto no contiene ningún número.

**D-013 · Series evaluadas.** Peso de trabajo = peso más frecuente entre las series de progresión (empate → el mayor). Se evalúan las series de progresión a ese peso, en orden, hasta `targetSets`; series extra se ignoran. Si hay menos series a ese peso que las objetivo, aplica la regla 3 (aunque el total de series sea suficiente: "cargas mezcladas").

**D-014 · Serie efectiva requiere ≥ 1 repetición** (o ≥ 1 segundo). Una serie "completada" con 0 repeticiones no cuenta como efectiva; nunca se rellena una pendiente con cero.

**D-015 · Detección de rendimiento inferior (revisada tras la revisión de la etapa 1).** Solo al **mismo peso**: menos repeticiones totales en las series que comparten ambas sesiones. Peso mayor: nunca es descenso (perder repeticiones tras subir es lo esperado). Peso menor: tampoco (es una elección del usuario, p. ej. tras una pausa larga "retomá con X o menos"; la versión anterior lo marcaba como caída y copiaba objetivos de otra carga). Además, la sesión anterior solo cuenta como "consecutiva" para las reglas 7/7b si no está separada de la última por más de `reassessAfterDays`.

**D-015b · Regla 7b sin condición de mismo peso.** Series < repMín en dos sesiones comparables consecutivas (a cualquier carga) → `reassess`, como dice 8.2-7.

**D-016 · RPE → RIR** como RIR = 10 − RPE cuando solo se registró RPE.

**D-017 · Chequeo de esfuerzo para subir**: se hace sobre la última sesión comparable; la regla de sesiones consecutivas exige además que las N últimas estén al tope del rango con el mismo peso.

**D-018 · Peso corporal.** La carga comparada es la carga neta adicional = adicional − asistencia (negativa = asistida). Al llegar al tope: con asistencia se reduce la asistencia; sin asistencia se sugiere sumar lastre (con nota "si no tenés lastre, seguí sumando repeticiones").

**D-019 · Duración.** Progresa en segundos (+`secondsIncrement` en series bajo el máximo). Al alcanzar `secondsMax` en todas: mantener y sugerir variante más difícil o carga (no se automatiza).

**D-020 · `ComparabilityLink` es simétrico y transitivo** (cierre transitivo determinista).

**D-021 · Tendencia (revisada).** Métrica: si las últimas ≥ 3 sesiones comparables comparten peso de trabajo → repeticiones (o segundos) totales a carga constante; si no, mejor 1RM estimado con tope si todas las sesiones lo tienen; si no, sin conclusión. (La versión anterior priorizaba el 1RM con tope de 10 reps, que en un rango 8–12 queda plano aunque las reps suban y daba un "posible estancamiento" falso.) Pendiente por mínimos cuadrados relativa a la media, ventana de 6 sesiones. Umbrales: +1 %/sesión progresando, −1 %/sesión **y** nuevo mínimo → descenso, rango ≤ 3 % → posible estancamiento, resto → estable (fluctuación nunca declara estancamiento). Menos de 3 sesiones → `insufficientData`.

**D-022 · La decisión previa no es entrada de reglas del motor.** La recomendación se congela al abrir el ejercicio y la decisión vive en `RecommendationDecision`; la próxima recomendación se calcula con lo **realizado** (caso 2.D-8).

**D-024 · Fusión de logs.** Primero se filtra al contexto equivalente y después se fusiona por sesión: dos máquinas vinculadas usadas en la misma sesión son **una** sesión comparable (antes contaban como dos y podían disparar "2 sesiones consecutivas"). Los logs se concatenan por orden de ejecución (primera serie completada) y el orden de series es total (desempata por RIR/RPE, etc.).

**D-025 · Modo A cuenta sesiones válidas, no días distintos** (la spec dice "sesiones válidas ≥ días planificados"). Dos sesiones el mismo día cuentan dos.

**D-026 · Calendario: plan semanal completo.** Cambiar el plan escribe 7 entradas nuevas (una por día, `nil` = descanso) con el mismo `validFrom` (`Schedule.weeklyPlanEntries`), así quitar un día es explícito y el pasado se reconstruye igual.

**D-027 · `WeightParser` rechaza "1.000" / "62.500"** (punto seguido de exactamente 3 dígitos): en es-AR el punto es separador de miles y leerlo como decimal sería un error silencioso.

**D-028 · Asistencia en peso corporal** baja de a `increment` sin usar `availableWeights` (las máquinas asistidas suelen tener pasos fijos); los récords (`PersonalRecords`) cubren solo `weightReps`.

**D-029 · Contexto por defecto de un log nuevo** = etiquetas (variante/máquina) del último log completado de ese ejercicio. Así, quien siempre entrena en "Máquina A" sigue comparando contra ella sin re-elegirla; cambiarla es un gesto explícito.

**D-030 · Decisiones.** Una `RecommendationDecision` por `ExerciseLog`. Si el usuario cambia de opinión se actualiza la misma (mismo id) conservando la recomendación mostrada originalmente. Cambiar de máquina **antes** de decidir recalcula y vuelve a congelar la recomendación para el nuevo contexto; **después** de decidir no se toca nada. "Ignorar" quita las cargas que una decisión previa había precargado (solo en series pendientes).

**D-031 · Sesión abierta única.** Solo puede haber una sesión `active`/`paused`; es la que se ofrece retomar al abrir la app. Descartar marca `discarded` (no borra; queda excluida de todo).

**D-032 · Completar en un toque.** Si faltan reps/segundos, `completeSet` usa el objetivo visible de la serie; el peso nunca se inventa (sin peso → error `missingValues`).

**D-033 · Import = merge por id** (nunca borra, todo o nada, valida esquema y referencias antes). Reimportar el mismo archivo no duplica. CSV: RFC 4180 con coma, punto decimal e ISO-8601 para que sea legible por cualquier herramienta.

**D-034 · Ids del catálogo**: UUIDv5 derivado del `catalogId` estable (`scripts/gen_catalog.py`), fijo en el JSON. Seeding idempotente: actualiza nombre/músculos/equipamiento de ejercicios de catálogo, conserva la configuración de progresión editada y el archivado, nunca toca los personalizados.

**D-023 · Pausa larga** ⇒ `reassess` con el último peso como referencia ("retomá con X o menos") y repeticiones objetivo = repMín. Días contados como días calendario en la zona horaria del usuario.
