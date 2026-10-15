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

**D-015 · Detección de rendimiento inferior.** Mismo peso: menos repeticiones totales en las series que comparten ambas sesiones. Peso menor (solo `weightReps`): mejor 1RM estimado menor (fórmula sin tope, solo para comparar). Peso mayor: nunca es "descenso" (bajar repeticiones tras subir carga es lo esperado).

**D-016 · RPE → RIR** como RIR = 10 − RPE cuando solo se registró RPE.

**D-017 · Chequeo de esfuerzo para subir**: se hace sobre la última sesión comparable; la regla de sesiones consecutivas exige además que las N últimas estén al tope del rango con el mismo peso.

**D-018 · Peso corporal.** La carga comparada es la carga neta adicional = adicional − asistencia (negativa = asistida). Al llegar al tope: con asistencia se reduce la asistencia; sin asistencia se sugiere sumar lastre (con nota "si no tenés lastre, seguí sumando repeticiones").

**D-019 · Duración.** Progresa en segundos (+`secondsIncrement` en series bajo el máximo). Al alcanzar `secondsMax` en todas: mantener y sugerir variante más difícil o carga (no se automatiza).

**D-020 · `ComparabilityLink` es simétrico y transitivo** (cierre transitivo determinista).

**D-021 · Tendencia.** Métrica: mejor 1RM estimado (con tope de repeticiones) si todas las sesiones lo tienen; si no, repeticiones totales en la racha final a carga constante. Pendiente por mínimos cuadrados relativa a la media, ventana de 6 sesiones. Umbrales: +1 %/sesión progresando, −1 %/sesión **y** nuevo mínimo → descenso, rango ≤ 3 % → posible estancamiento, resto → estable (fluctuación nunca declara estancamiento). Menos de 3 sesiones → `insufficientData`.

**D-022 · La decisión previa no es entrada de reglas del motor.** La recomendación se congela al abrir el ejercicio y la decisión vive en `RecommendationDecision`; la próxima recomendación se calcula con lo **realizado** (caso 2.D-8).

**D-023 · Pausa larga** ⇒ `reassess` con el último peso como referencia ("retomá con X o menos") y repeticiones objetivo = repMín. Días contados como días calendario en la zona horaria del usuario.
