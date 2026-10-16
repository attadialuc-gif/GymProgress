# Paridad iOS ⇄ Android / Windows

La app de Android y Windows (`crossplatform/`, Flutter) es un port de la app de iPhone. El motor y los datos son los mismos; la interfaz se adapta a cada plataforma. Este documento lista qué es igual, qué cambia por plataforma y qué diferencias quedan.

## Igual en las tres plataformas (verificado con tests)

- **Motor de sobrecarga progresiva** (sección 2): mismas reglas, mismos textos en español y mismos números. Los 8 casos 2.D, el determinismo y la no comparabilidad dan resultados idénticos a Swift (fixtures generados por el código Swift; 113 tests en `gym_core`).
- **Persistencia y servicios**: decisiones Aceptar / Modificar / Ignorar guardadas y nunca pisadas por un recálculo, recuperación de la sesión abierta, historial inmutable, calendario con `validFrom`, rachas, estadísticas, récords y objetivos. Los 42 escenarios de los tests de GymStore de Swift dan observaciones idénticas (62 tests en `gym_store`).
- **Copias de seguridad**: el JSON de exportación es el mismo contrato (`schemaVersion` 1). Una copia del iPhone se importa en Android/Windows sin pérdida y una copia de Android/Windows se importa en el iPhone (verificado con `FixtureExporter verify-import`). Importar nunca duplica ni pisa datos.
- **Secciones**: Inicio, Rutinas (con biblioteca de 98 ejercicios), Entrenar, Progreso, Perfil; superseries, temporizador de descanso por marca de tiempo, calendario mensual/semanal con plan semanal, filtros de período y por rutina, gráficos por máquina/variante, volumen por músculo (directas e indirectas, objetivos propios), récords reales vs. estimados, objetivos, ajustes completos, export JSON y CSV, import JSON.
- Tema oscuro por defecto, textos y números en es-AR (coma decimal; también se acepta punto), kg o lb (siempre se guarda en kg).

## Adaptaciones de Android

| Tema | Cómo se resolvió |
|---|---|
| Teclado decimal | Teclado numérico con decimales; según el teclado del teléfono aparece coma o punto: la app acepta los dos. |
| Aviso de fin de descanso | Notificación local programada. El permiso de notificaciones (Android 13+) se pide la primera vez que corre un descanso, nunca al abrir la app. |
| Alarma exacta | Si el sistema permite alarmas exactas se usan; si no, se programa una inexacta (puede llegar unos segundos tarde) — nunca falla. En Perfil hay un acceso para permitir avisos puntuales. |
| Pantalla encendida | Durante un entrenamiento abierto, si está activado en Perfil (igual que iOS). |
| Hápticos | Vibración breve al completar una serie. |
| Botón atrás | Vuelve dentro de la sección (pantallas y paneles); solo sale de la app desde la raíz de la sección. |
| Cierre forzado del proceso | Cada serie se guarda al instante (SQLite, transacción por cambio). Al reabrir se ofrece retomar el entrenamiento, con decisiones y tarjeta de recomendación intactas; el descanso en curso se restaura. |

## Adaptaciones de Windows

| Tema | Cómo se resolvió |
|---|---|
| Diseño | Navegación lateral en ventanas anchas (≥ 720 px) y barra inferior en angostas. |
| Ventana | Redimensionable, tamaño inicial 1100 × 800, mínimo 380 × 560 (escalado por DPI). |
| DPI | Per-Monitor V2 (manifiesto de Flutter): nítido en pantallas con escala. |
| Atajos de teclado | Ctrl+1…5 cambia de sección, Esc vuelve atrás, Ctrl+Enter completa la siguiente serie pendiente del ejercicio abierto. |
| Hápticos | No hay (sin efecto). |
| Fin de descanso | Sonido del sistema + notificación de Windows mientras la app está abierta. |
| Datos | Carpeta del usuario: `%APPDATA%\GymProgress\GymProgress\gymprogress.sqlite` (nunca en la carpeta de instalación). |
| Cerrar la ventana | Lo escrito en una serie se guarda antes de salir. |

## Diferencias conocidas con iOS

- **Exportar/compartir**: en iPhone se comparte con la hoja de compartir; en Android/Windows se abre el diálogo "Guardar como" del sistema.
- **Notificaciones en Windows**: el aviso de fin de descanso suena si la app está abierta (lo habitual en una PC); no se programa en segundo plano.
- **Precisión de instantes**: microsegundos en Android/Windows (iOS guarda un `Double`). Reimportar en el iPhone una copia hecha en Android con los mismos registros puede informar "conflictos" (se conserva la versión local; nada se duplica). D-104.
- **Dos detalles donde Android/Windows se comportan mejor que iOS** (iOS no se modificó en este trabajo): un peso inicial inválido no se guarda a medias, y el CSV entrecomilla siempre los saltos de línea. D-105.
- **Formato de números** solo es-AR y en-US; zonas horarias IANA. D-104.
- Sin widgets, integraciones de salud ni sincronización (tampoco existen en iOS).

## No verificado

- Instalación y uso en el teléfono y la PC del usuario (no hay acceso a esos dispositivos). Se verificó: build de Android y Windows en CI, tests unitarios/widget en Linux y el flujo 2.E de punta a punta en un Windows real del runner de CI.
- Comportamiento de las notificaciones y la pantalla encendida en dispositivos concretos (dependen del fabricante y de los permisos que el usuario otorgue).
