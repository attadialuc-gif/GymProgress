# Registro de decisiones

Formato: decisión · alternativas · motivo. Las decisiones del motor (D-010+) explican cómo se resolvieron ambigüedades entre las secciones 2 y 8 (manda la sección 2).

## Multiplataforma: Android y Windows (rama `feat/crossplatform`)

**D-100 · Flutter + Dart para Android y Windows.** La app iOS no se toca; todo lo nuevo vive en `crossplatform/`.

| Opción | Android | Windows | Reusa lógica Swift | Contras decisivos |
|---|---|---|---|---|
| **Flutter + Dart** (elegida) | Nativo AOT, maduro | Nativo (Win32/AOT), maduro | No (port + fixtures dorados) | Hay que portar GymCore/GymStore |
| Compose Multiplatform (Kotlin) | Excelente | Desktop sobre JVM (JRE embebido, más pesado, look menos nativo) | No | Necesita JDK; port igual de grande |
| TypeScript + Capacitor / Tauri | WebView | WebView2 | No | Es una página web en un contenedor: excluido por la consigna |
| Swift en Android/Windows (SDK de Android de Swift, Swift para Windows) | Lógica sí; UI no (sin SwiftUI): JNI + UI nativa aparte | Lógica sí; UI WinUI vía interop inmaduro | Sí (solo la lógica) | Dos UIs nuevas + puentes FFI/JNI + toolchains pesados en CI; la UI hay que rehacerla igual |

Motivo: un solo código de UI para ambas plataformas, binarios nativos, offline, núcleo en Dart puro testeable con `dart test` en WSL. El riesgo del port se controla con **fixtures dorados exportados desde el código Swift** (D-101).

**D-101 · Fidelidad por fixtures.** Un ejecutable Swift (`GymCore/Sources/FixtureExporter`, sin cambiar lógica) serializa a JSON entrada y salida de los casos de GymCore/GymStore; el port Dart debe reproducirlos exactamente (con tolerancia numérica documentada). Una diferencia es un bug del port, salvo que se demuestre un bug en Swift (se corrige en ambos lados con test).

**D-102 · Persistencia Dart: SQLite vía `package:sqlite3`** (FFI, sin generación de código) con migraciones por `PRAGMA user_version`, mismo esquema conceptual que SwiftData (columnas indexadas + payload JSON del registro). · Alternativa: drift (requiere `build_runner` y codegen; más dependencias). El formato de intercambio entre plataformas es el JSON de exportación con `schemaVersion` (mismo contrato que iOS).

**D-103 · Semántica de texto de Swift reproducida con fixtures.** Normalizar etiquetas de contexto (máquina/variante) depende de Foundation: recorte con `.whitespacesAndNewlines`, plegado `folding([.caseInsensitive, .diacriticInsensitive], es_AR)` y separación por `Character.isWhitespace`. En vez de aproximarlo, el exportador vuelca el plegado Swift de cada carácter de los bloques latino, griego y cirílico (`parsing.json` → `fold`) y se genera `gym_core/lib/src/fold_table.g.dart` con `dart run tool/gen_fold_table.dart` (regenerar si cambian los fixtures; un test compara cada fila con Swift). Las marcas combinantes se eliminan (texto NFD) y fuera de esos bloques se usa minúscula. Observado en Swift y replicado: `ß→ss`, `Ø→ø`, `ł`/`đ` se mantienen; U+FEFF no es espacio; U+0085, NBSP y U+200B se recortan. La identidad de un contexto normalizado es `identityKey` (sin ambigüedad); `sortKey` (igual a Swift) solo ordena.

**D-104 · Límites conocidos del port (documentados, sin efecto en el uso normal).**
- Instantes con precisión de microsegundo en Dart (Swift guarda `Double`). Importar un export de iPhone conserva el instante al µs; reimportar en el iPhone el export de Android con los mismos registros puede informar "conflictos" (versión local conservada, nada se duplica ni se pisa).
- Formato de números: solo es-AR (app) y en-US (verificación), como Swift con esos locales; ICU muestra "-0" para negativos que redondean a cero y Dart también.
- Zonas horarias: identificadores IANA (los que entrega el sistema operativo); abreviaturas como "GMT-0300" no se aceptan.
- `DateTime` locales y UTC se comparan por instante (`compareTo`), nunca con `==`.

**D-105 · Store Dart: integridad ante fallas (revisión de la etapa C).**
- Base con registros ilegibles → no se abre (igual que el store JSON de Swift): nunca se sobrescribe un registro dañado ni se exporta incompleto. La app muestra la pantalla de bloqueo.
- Cada llamada de servicio con varias escrituras (empezar sesión, decidir, completar serie, importar, plan semanal, etc.) corre en `repository.transaction`: todo o nada. Dentro de un lote cada escritura usa `SAVEPOINT`.
- Errores de codificación (NaN/∞) son `storage` y no escriben nada. Búsquedas por id sin distinguir mayúsculas (como `UUID` en Swift).
- Orden de nombres es-AR: la ñ es una letra propia después de la n (como `localizedCompare` en un iPhone en español).
- **Bugs de Swift detectados y no corregidos en iOS** (esta tarea prohíbe tocar la app iOS; quedan como mejora pendiente): (1) `setInitialTarget` guarda el peso inicial antes de validar; en Dart la transacción lo revierte; (2) el CSV no entrecomilla campos con `\r\n` (Swift compara `Character` y CRLF es un solo grafema); Dart sí lo hace. Ninguno afecta el motor ni los datos registrados normalmente (la UI no permite pesos negativos ni saltos de línea en nombres de rutina).
- Igual que Swift, a propósito: abrir un ejercicio de una sesión terminada que nunca se abrió congela una recomendación (la UI solo abre ejercicios de la sesión en curso).

**D-106 · Adaptaciones de plataforma (Android/Windows).** Notificación de fin de descanso con `flutter_local_notifications` (Android: programada, exacta si el sistema lo permite y si no inexacta; permiso pedido en contexto; Windows: sonido + aviso con la app abierta). Pantalla encendida con `wakelock_plus` solo durante una sesión abierta y si el usuario lo activó. Descanso en curso restaurado tras un cierre del proceso (archivo `rest_timer.json` en la carpeta de datos; solo comodidad, nunca datos de entrenamiento). Atrás de Android decidido al momento del gesto (navegadores anidados por sección). Atajos de teclado en escritorio. Ventana mínima 380 × 560 escalada por DPI. Export/import con el diálogo del sistema (`file_picker`). Gráficos con `fl_chart`. Ninguna dependencia usa red. Detalle en `docs/PARIDAD.md`.
- Valores en lb: lo que se muestra redondeado no reescribe el kg guardado si el usuario no lo cambió (hallazgo de la revisión de la etapa D; el mismo problema existe en iOS y no se modificó).

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

**D-033 · Import = solo agrega lo nuevo (revisada tras la revisión de etapas 2–3).** Nunca sobrescribe ni borra registros locales: si el archivo trae una versión distinta de un registro existente, gana la local y se informa como conflicto (una copia vieja nunca deshace un entrenamiento más nuevo). Se rechaza el import si hay un entrenamiento abierto local y el archivo trae otro abierto. Los ajustes se importan solo en una app sin historial (restauración). Todo o nada; valida esquema, referencias (incluido el ejercicio de cada log), valores y decisiones duplicadas. Reimportar no duplica. CSV: RFC 4180 con coma, punto decimal e ISO-8601.

**D-035 · Cambios estructurales solo con la sesión abierta.** Decidir, completar/reabrir/agregar/quitar series, cambiar contexto o quitar ejercicios exige sesión `active`/`paused`; el historial terminado no se reindexa. Editar valores de una serie se permite siempre (corregir un error de tipeo), pero `updateSet` nunca cambia el estado completada/pendiente.

**D-036 · "Tratar como equivalente"** vincula el contexto que el usuario venía usando con el nuevo (no con el estándar) y después cambia el contexto, así la tarjeta de hoy (si todavía no hay decisión) ya compara con ese historial (`switchContextTreatingAsEquivalent`).

**D-037 · Objetivo inicial** se guarda donde lo leerá la próxima sesión: en el override de la rutina si existe, si no en el ejercicio; y se usa hoy como decisión `modified`. La vista previa de "próxima sesión" usa la configuración de la rutina con la que se hizo el ejercicio la última vez.

**D-038 · Copiar cargas** usa solo la última sesión comparable; copiar desde otro contexto requiere un botón explícito rotulado "no equivalente".

**D-039 · Registro de series en la UI:** los campos se guardan al salir del campo, al confirmar y siempre antes de completar la serie (no en cada tecla); mostrar un valor nunca lo reescribe. Si la base de datos no abre, la app muestra una pantalla bloqueante en lugar de aceptar entrenamientos en un almacenamiento temporal. "Pantalla encendida" se maneja desde la raíz mientras haya sesión abierta.

**D-034 · Ids del catálogo**: UUIDv5 derivado del `catalogId` estable (`scripts/gen_catalog.py`), fijo en el JSON. Seeding idempotente: actualiza nombre/músculos/equipamiento de ejercicios de catálogo, conserva la configuración de progresión editada y el archivado, nunca toca los personalizados.

**D-040 · Plan semanal (revisada tras la revisión de etapas 4–7).** `validFrom` nunca es anterior a hoy (el servicio lo recorta y el selector de fecha no lo permite), así un cambio no reescribe días pasados. Entre entradas vigentes gana la **creada más recientemente** (desempate: `validFrom` más tardío): la última decisión del usuario manda desde su fecha, incluso sobre un plan guardado antes para una fecha posterior.

**D-041 · Récords, gráficos y objetivos por contexto comparable.** Se calculan por clase de contexto (máquina/variante/modo de carga, más los vínculos del usuario); nunca se mezclan. Por defecto se usa la clase del contexto usado por última vez; Progreso y Récords muestran las demás por separado y rotuladas. Un primer registro en un contexto nuevo no es un "récord superado".

**D-042 · Comparación de períodos a la fecha.** Para semana, mes y año en curso se compara el mismo número de días transcurridos con el período anterior ("a la fecha vs. los mismos días"); los períodos móviles se comparan completos.

**D-043 · Récords recientes.** Solo cuentan si una sesión anterior ya tenía un registro de ese tipo en ese contexto; uno por (ejercicio, contexto, tipo, sesión), el mejor de la sesión.

**D-044 · Objetivos de series semanales por músculo** opcionales en `UserSettings.muscleSetGoals` (solo si el usuario los define; la app no propone un número). Los objetivos por ejercicio se fechan el día del récord que los alcanzó.

**D-045 · Superseries en la UI.** Un calentamiento no forma parte de la ronda (descanso normal). Pasar al siguiente ejercicio reemplaza la pantalla actual en lugar de apilarla; dentro de la ronda se detiene un temporizador previo.

**D-046 · Próximo entrenamiento en Inicio:** con plan, el próximo día planificado (hoy salvo que ya se entrenó o sea descanso); sin plan, la rutina siguiente a la última hecha. Días y semanas siguen la zona horaria actual del dispositivo.

**D-047 · CSV:** columnas `measurement` y `load_mode` (`weight_kg` es por lado en `perSide`) y textos que empiezan con `=`, `+`, `-` o `@` se prefijan con `'` para que una planilla no los ejecute como fórmula.

**D-048 · Compilación iOS en GitHub Actions.** Sin Mac, la app se compila en un runner macOS (`.github/workflows/build-ios.yml`, Xcode 26.6 / Swift 6.3.3 en el primer run verde): tests de paquetes, build sin firmar para iPhone empaquetado como `.ipa` (lo firma el usuario con Sideloadly) y tests de la app en un simulador elegido con `xcrun simctl`. Repo público ⇒ dispara en cada push a `main`.

**D-049 · Un solo framework dinámico `GymKit`** (módulos `GymCore` + `GymStore`) enlazado por la app y su bundle de tests: una única copia de los tipos y del bundle de recursos. Dos productos dinámicos separados no compilan (GymCore quedaría enlazado dos veces). El framework se **embebe** en la app (`embed: true`) y el CI falla si alguna dependencia `@rpath` del ejecutable no está dentro del `.app` (el primer `.ipa` verde no lo tenía y no habría abierto en un iPhone).

**D-050 · La app compila en modo Swift 6 con concurrencia estricta** (no hizo falta bajar a Swift 5). `BUNDLE_ID` se cambia solo en `project.yml` (marcador `com.example.gymprogress`).

**D-023 · Pausa larga** ⇒ `reassess` con el último peso como referencia ("retomá con X o menos") y repeticiones objetivo = repMín. Días contados como días calendario en la zona horaria del usuario.
