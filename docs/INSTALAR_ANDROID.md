# Instalar GymProgress en Android

Archivo: `dist/GymProgress.apk` (firmado con la clave de la app; siempre la misma, así las actualizaciones se instalan encima sin perder datos).

La app no usa internet, no tiene cuentas ni publicidad y guarda todo en el teléfono.

## 1. Pasar el APK al teléfono

Elegí una opción:

- **Cable USB**: conectá el teléfono a la PC, en el teléfono elegí *Transferencia de archivos* en el aviso de USB, y copiá `GymProgress.apk` a la carpeta **Descargas** (Download) del teléfono.
- **Google Drive / OneDrive**: subí el archivo desde la PC y descargalo desde la app de Drive en el teléfono.
- **Mandártelo a vos mismo** (WhatsApp "Mensajes guardados", Telegram, correo): enviá el archivo y descargalo en el teléfono.

> Si algún servicio lo bloquea por ser un `.apk`, usá el cable USB o Drive.

## 2. Permitir la instalación

Android pide permiso la primera vez que instalás una app fuera de Play Store ("orígenes desconocidos"):

1. Abrí **Archivos** (o *Mis archivos*) → **Descargas** → tocá `GymProgress.apk`.
2. Aparece *"Por tu seguridad, tu teléfono no puede instalar apps desconocidas de esta fuente"* → **Configuración** → activá **Permitir desde esta fuente** → volvé atrás.
3. Tocá **Instalar**.

El permiso queda asociado a la app desde la que abriste el APK (Archivos, Drive, Chrome…). Podés desactivarlo después en *Ajustes → Apps → Acceso especial → Instalar apps desconocidas*.

## 3. Aviso de Play Protect

Como la app no viene de Play Store, Google Play Protect puede mostrar **"App no segura detectada"** o **"Bloqueada por Play Protect"**:

- Tocá **Más detalles** → **Instalar de todas formas** (o *Instalar sin analizar*).
- Si ofrece *"Enviar la app para que se analice"*, podés aceptar o rechazar; no cambia nada en la app.

Es el aviso normal para cualquier app instalada a mano.

## 4. Primer uso

- Al terminar el primer descanso entre series, Android 13 o superior pregunta si la app puede **enviar notificaciones**: aceptá si querés el aviso de fin de descanso.
- Opcional: *Perfil → Permitir avisos puntuales* para que el aviso llegue en el segundo exacto (sin ese permiso puede demorarse unos segundos).
- *Perfil → Mantener pantalla encendida en sesión* evita que se apague la pantalla durante el entrenamiento.

## 5. Pasar tus datos desde el iPhone (o desde otra instalación)

1. En la app de origen: **Perfil → Exportar copia completa (JSON)** y guardá el archivo (en iPhone: *Compartir* → Archivos, Drive o correo).
2. Llevá el `.json` al teléfono Android (igual que el APK).
3. En Android: **Perfil → Importar / restaurar copia…** → elegí el archivo.

La importación solo agrega lo que no existe: nunca borra ni pisa lo que ya tenés. Incluye entrenamientos, decisiones sobre recomendaciones, rutinas, plan semanal, objetivos y ajustes (los ajustes solo si la app está vacía).

## 6. Actualizar

Instalá el nuevo `GymProgress.apk` encima (pasos 1–3). Los datos se conservan porque la firma es la misma.

## 7. Desinstalar

*Ajustes → Apps → GymProgress → Desinstalar* (o mantené presionado el ícono → *Desinstalar*).

**Desinstalar borra los datos de la app.** Antes, exportá una copia (*Perfil → Exportar copia completa*).

## Si algo falla

| Paso | Problema | Qué hacer |
|---|---|---|
| 1 | No encuentro el archivo en el teléfono | Abrí *Archivos* → *Descargas*, o buscá "GymProgress". Si usaste Drive, descargalo primero (⋮ → Descargar). |
| 1 | El servicio no deja enviar `.apk` | Usá cable USB o Google Drive. |
| 2 | No aparece la opción "Permitir desde esta fuente" | *Ajustes → Apps → Acceso especial → Instalar apps desconocidas* → elegí la app con la que abrís el APK → *Permitir*. En algunos teléfonos está en *Ajustes → Seguridad*. |
| 2 | "La app no está instalada" / "Paquete no válido" | El archivo se copió incompleto: volvé a copiarlo. Si ya tenías una versión instalada con otra firma, desinstalala primero (exportá tus datos antes). |
| 2 | "Se analizó la app, pero no es compatible" | El teléfono tiene una versión de Android demasiado vieja para esta app. |
| 3 | Play Protect no deja instalar | *Más detalles → Instalar de todas formas*. Si no aparece, en Play Store → foto de perfil → *Play Protect* → ⚙ → desactivá *Analizar apps* solo mientras instalás y volvé a activarlo después. |
| 4 | No llega el aviso de fin de descanso | *Ajustes → Apps → GymProgress → Notificaciones* → activadas. Revisá también el modo No molestar y el ahorro de batería (*Batería → Sin restricciones* para GymProgress). |
| 5 | "El archivo no es una copia válida de GymProgress" | Elegí el `.json` exportado por la app (no el CSV). Si lo abriste con otra app y lo guardaste de nuevo, exportalo otra vez. |
| 5 | "Terminá o descartá el entrenamiento en curso…" | Hay un entrenamiento abierto en el teléfono y otro en la copia: finalizá o descartá el del teléfono e importá de nuevo. |
