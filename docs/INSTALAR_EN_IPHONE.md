# Instalar GymProgress en tu iPhone desde Windows

El `.ipa` que genera el CI **no está firmado**. Para instalarlo lo firmás vos con **Sideloadly** y un **Apple ID gratuito**. Tu Apple ID y tu contraseña se escriben solo en Sideloadly (que habla con Apple); nunca se guardan en este proyecto.

## Requisitos

- iPhone con **iOS 17 o superior** y su cable USB.
- PC con Windows.
- **iTunes** e **iCloud para Windows**, instalados desde el sitio de Apple (Sideloadly recomienda las versiones del sitio de Apple, no las de Microsoft Store; si ya tenés las de la Store y Sideloadly no detecta el iPhone, cambialas).
- **Sideloadly**, desde su sitio oficial: https://sideloadly.io
- El archivo `GymProgress.ipa` (en `dist\GymProgress.ipa` dentro de la carpeta del proyecto, o descargado como artifact `GymProgress-ipa` del run de GitHub Actions).

## Paso a paso

1. **Conectá el iPhone** por USB, desbloquealo y, si pregunta, tocá **Confiar en esta computadora**.
2. **Abrí iTunes** una vez para comprobar que ve el iPhone. Después podés cerrarlo.
3. **Abrí Sideloadly.**
   - En el desplegable de dispositivos tiene que aparecer tu iPhone.
   - Arrastrá `GymProgress.ipa` al recuadro del ícono (o tocá el ícono del .ipa y elegilo).
   - En **Apple account** escribí tu Apple ID.
4. Tocá **Start**. Sideloadly te pide la contraseña del Apple ID (y el código de doble factor si lo tenés). Espera a que diga **Done**.
5. **Activá el Modo desarrollador en el iPhone** (iOS 16 o superior, solo la primera vez):
   Ajustes → Privacidad y seguridad → **Modo desarrollador** → activar → el iPhone se reinicia → al volver, confirmá **Activar**.
6. **Confiá en tu certificado**:
   Ajustes → General → **VPN y gestión de dispositivos** → tocá tu Apple ID en "App de desarrollador" → **Confiar**.
7. Abrí **GymProgress**.

## Limitaciones del Apple ID gratuito

- La app **deja de abrir a los 7 días**. Para renovarla, volvé a instalar el mismo `.ipa` con Sideloadly antes de que venza (Sideloadly tiene una opción de *auto-refresh*). Reinstalar con el mismo Apple ID y el mismo identificador de app **conserva tus datos**.
- Máximo **3 apps** instaladas así a la vez, y un número limitado de identificadores de app nuevos por semana.
- **Antes de reinstalar o cambiar algo**, hacé una copia: Perfil → **Exportar copia completa (JSON)** → compartila a Archivos o a tu PC. Si el identificador de la app cambia (por ejemplo, si Sideloadly lo modifica en "Advanced options"), iOS la trata como otra app y los datos no pasan solos; se recuperan con **Importar / restaurar copia**.

## Identificador de la app (bundle ID)

El proyecto usa `com.example.gymprogress` como marcador. Sideloadly puede firmarlo tal cual con tu Apple ID gratuito; si diera error de identificador, en **Advanced options** activá el cambio automático de bundle ID. Para cambiarlo de forma permanente, editá **solo** `BUNDLE_ID` en `project.yml` y volvé a correr el workflow.

## Si algo falla

- **"Device not found"**: reinstalá iTunes/iCloud desde el sitio de Apple, cambiá el cable o el puerto, desbloqueá el iPhone y aceptá "Confiar".
- **"Guru Meditation" / error de login**: revisá la contraseña o el código de doble factor; Sideloadly a veces necesita reintentarse.
- **La app se cierra al abrir (o dice "no disponible")**: venció la firma de 7 días o falta "Confiar" en el certificado (paso 6).

> Esta guía no se pudo probar en un iPhone real desde el entorno donde se escribió: es el procedimiento estándar de Sideloadly con un Apple ID gratuito.
