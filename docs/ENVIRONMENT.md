# Entorno de desarrollo (etapa 0)

Fecha de inspección: 2026-10-15.

## Resultado de la inspección

Comandos pedidos en la sección 4, ejecutados en Git Bash sobre Windows:

| Comando | Resultado |
|---|---|
| `uname -a` | `MINGW64_NT-10.0-26300 … x86_64 Msys` (Windows 11 Home 10.0.26300) |
| `sw_vers` | no existe (no es macOS) |
| `xcodebuild -version` | `command not found` |
| `xcode-select -p` | `command not found` |
| `swift --version` | `command not found` (en Windows) |
| `xcrun simctl list devices available` | `command not found` |
| `which xcodegen tuist swiftlint` | ninguno instalado |
| `git --version` | `git version 2.55.0.windows.5` |

Otros hallazgos:

- WSL 2 disponible con la distro `kali-linux` (Kali Rolling 2026.1, glibc 2.42, sin `sudo` sin contraseña).
- Windows bloquea que `bash.exe`/`powershell.exe` creen archivos dentro de `Documents` (comportamiento típico de *Acceso controlado a carpetas*). No se tocó esa configuración de seguridad. Los procesos de WSL sí pueden escribir; por eso git y el toolchain de Swift se ejecutan desde WSL.

## Decisión (tabla de la sección 4)

Situación: **"Linux u otro sistema sin Xcode"**.

- `GymCore` (dominio + motor de progresión + métricas) y `GymStore` (capa de aplicación independiente de la persistencia) se implementan como Swift Package puro y se verifican con `swift test` en Linux (WSL).
- La capa iOS (SwiftUI, SwiftData, Swift Charts, notificaciones) se escribe completa pero **no se puede compilar ni ejecutar aquí**: queda marcada como **no verificada** hasta compilarla en un Mac con Xcode.

## Toolchain instalado (con autorización del usuario)

- Swift **6.4.1** (`swift-6.4.1-RELEASE`, build oficial de swift.org para Debian 13), descomprimido en `~/swift/` dentro de WSL, sin privilegios de administrador.
  - Firma GPG del tarball: ver "Verificación" abajo.
- `libxml2.so.2` (paquete oficial de Debian 13 `libxml2_2.12.7+dfsg+really2.9.14-2.1+deb13u3`) extraído en `~/swift/extra-libs/` porque Kali trae solo `libxml2.so.16` y `swift-test` necesita la versión `.so.2`.

```
$ swift --version
Swift version 6.4.1 (swift-6.4.1-RELEASE)
Target: x86_64-unknown-linux-gnu
```

## Cómo correr los tests aquí (Windows + WSL)

```bash
# dentro de WSL
export PATH="$HOME/swift/swift-6.4.1-RELEASE-debian13/usr/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/swift/extra-libs"
cd "<ruta del repo vista desde WSL>/GymCore"
swift test
```

(En la práctica se sincroniza `GymCore/` a `~/gymprogress/GymCore` con `rsync` y se compila ahí: es mucho más rápido que compilar sobre `/mnt/c`.)

## Cómo compilar la app iOS (requiere Mac)

1. macOS 14+ con Xcode 16+ (iOS 17 SDK o superior) y un simulador de iPhone.
2. `brew install xcodegen`
3. En la raíz del repo: `xcodegen generate` → genera `GymProgress.xcodeproj` a partir de `project.yml`.
4. `xcodebuild -scheme GymProgress -destination 'platform=iOS Simulator,name=iPhone 16' test`

## Qué falta para el camino completo

- Un Mac con Xcode (no disponible en esta máquina). Sin eso no se puede: compilar SwiftUI/SwiftData, correr tests de persistencia SwiftData, tests de UI ni probar en simulador.
