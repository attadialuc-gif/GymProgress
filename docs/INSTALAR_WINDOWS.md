# Instalar GymProgress en Windows

Dos opciones (Windows 10 u 11 de 64 bits):

- **Instalador**: `dist/GymProgress-Setup.exe` — crea el acceso en el menú Inicio (y en el escritorio si lo elegís). No pide permisos de administrador: se instala solo para tu usuario.
- **Portable**: `dist/GymProgress-windows.zip` — descomprimís y ejecutás `GymProgress.exe`, sin instalar nada.

La app no usa internet, no tiene cuentas ni publicidad. Tus datos se guardan en tu usuario de Windows:
`%APPDATA%\GymProgress\GymProgress\gymprogress.sqlite`
(pegá esa ruta en la barra del Explorador para abrir la carpeta). Las dos opciones usan la misma carpeta de datos.

## 1. Instalador

1. Doble clic en `GymProgress-Setup.exe`.
2. **Aviso de SmartScreen** ("Windows protegió tu PC"): aparece porque el instalador no está firmado con un certificado comercial. Hacé clic en **Más información** → **Ejecutar de todas formas**.
3. Seguí el asistente (en español): carpeta de instalación, acceso directo en el escritorio (opcional) → **Instalar** → **Finalizar** (abre la app).

## 2. Portable (zip)

1. Clic derecho en `GymProgress-windows.zip` → **Extraer todo…** → elegí una carpeta (por ejemplo `Documentos\GymProgress`).
2. Abrí la carpeta `GymProgress` y doble clic en `GymProgress.exe`.
3. Si aparece SmartScreen: **Más información** → **Ejecutar de todas formas**.

No muevas `GymProgress.exe` fuera de su carpeta: necesita los archivos que están a su lado.

## 3. Uso en la PC

- La ventana se puede agrandar o achicar; con la ventana ancha la navegación queda a la izquierda.
- Atajos: **Ctrl+1…5** cambia de sección (Inicio, Rutinas, Entrenar, Progreso, Perfil), **Esc** vuelve atrás, **Ctrl+Enter** completa la siguiente serie del ejercicio abierto.
- Al terminar un descanso suena el aviso de Windows (si está activado en *Perfil → Aviso al terminar el descanso*).
- Los números se escriben con coma o con punto decimal (62,5 o 62.5).

## 4. Pasar tus datos desde el iPhone o desde Android

1. En la app de origen: **Perfil → Exportar copia completa (JSON)**.
2. Llevá el archivo a la PC (correo, Drive, cable).
3. En Windows: **Perfil → Importar / restaurar copia…** → elegí el `.json`.

La importación solo agrega lo que no existe: nunca borra ni pisa lo que ya tenés.

## 5. Actualizar

Ejecutá el instalador nuevo encima (o reemplazá la carpeta del zip). Los datos se conservan: viven en `%APPDATA%`, no en la carpeta de la app.

## 6. Desinstalar

- **Instalador**: *Configuración → Aplicaciones → Aplicaciones instaladas → GymProgress → Desinstalar*.
- **Portable**: borrá la carpeta donde lo descomprimiste.

En los dos casos **tus datos quedan** en `%APPDATA%\GymProgress`. Para borrarlos también, exportá antes una copia si la querés y luego eliminá esa carpeta.

## Si algo falla

| Paso | Problema | Qué hacer |
|---|---|---|
| 1, 2 | SmartScreen no muestra "Ejecutar de todas formas" | Hacé clic primero en **Más información**. Si tu PC la administra una empresa o escuela, la directiva puede impedirlo: probá la versión portable o consultá al administrador. |
| 1, 2 | El navegador dice que el archivo "no se descarga habitualmente" | En la descarga: **…** → **Conservar** → **Mostrar más** → **Conservar de todas formas**. |
| 1, 2 | El antivirus pone el archivo en cuarentena | Es un falso positivo habitual con programas sin firma comercial. Restauralo desde el antivirus (Seguridad de Windows → Protección contra virus → Historial de protección → Permitir). |
| 2 | Falta un archivo `.dll` al abrir | Extraé el zip completo (no abras el `.exe` desde dentro del zip sin extraer). |
| 3 | La app abre en blanco o se cierra | Actualizá Windows (Windows Update) y el controlador de video, y volvé a abrirla. |
| 3 | No suena el aviso de descanso | *Perfil → Aviso al terminar el descanso* activado; revisá el volumen y el modo *No molestar* / *Asistente de concentración* de Windows. |
| 4 | "El archivo no es una copia válida de GymProgress" | Elegí el `.json` exportado por la app (no el CSV). |
| — | Aparece "No se pudieron abrir tus datos" | No registres entrenamientos. Cerrá la app y volvé a abrirla; si sigue, hacé una copia de la carpeta `%APPDATA%\GymProgress` antes de cualquier otra cosa. |
