# NTFSMate

Utilidad de barra de menú para macOS (Intel) que detecta USBs al instante,
formatea como NTFS y monta con lectura/escritura a la máxima velocidad que
permite el stack open-source disponible en macOS.

**Target declarado: macOS Sequoia (15.0+).** La arquitectura (FUSE/kext +
`SMAppService`) no usa ninguna API exclusiva de Sequoia — en principio corre
igual en Ventura/Sonoma — pero el deployment target y `LSMinimumSystemVersion`
están fijados en 15.0 porque es el único macOS que este proyecto garantiza y
prueba por ahora. Si más adelante se necesita Ventura de nuevo, basta con bajar
`MACOSX_DEPLOYMENT_TARGET` en `project.yml` y `LSMinimumSystemVersion` en el
Info.plist de la app — no hay refactor de código de por medio.

## Arquitectura

```
┌─────────────────────────┐        XPC (mach service)        ┌───────────────────────────┐
│   NTFSMate.app           │ ───────────────────────────────▶ │  NTFSHelper (root daemon)  │
│   - DiskArbitration      │                                   │  - diskutil unmountDisk    │
│     (detección USB)      │ ◀─────────────────────────────── │  - mkntfs (formatear)      │
│   - SwiftUI menú         │        resultado / error          │  - ntfs-3g (montar)        │
└─────────────────────────┘                                   └───────────────────────────┘
                                                                         │
                                                                         ▼
                                                        macFUSE (kext clásico, Intel)
                                                        + ntfs-3g como motor NTFS R/W
```

**Por qué este stack:**

- **Detección instantánea de USB** → `DiskArbitration` (`DARegisterDiskAppearedCallback`).
  Es push-based: no hay polling de `/Volumes`, así que una unidad nueva se reporta
  en el mismo tick de runloop en que el kernel la anuncia.
- **Motor NTFS (lectura/escritura)** → `macFUSE` + `ntfs-3g`. En Intel, macFUSE todavía
  puede cargar como **kernel extension clásica** (no como System Extension), que es
  la ruta rápida: evita el overhead adicional de IPC que tiene el modelo de extensión
  de sistema que Apple fuerza en Apple Silicon. Por eso este proyecto fija
  `ARCHS: x86_64` — en Apple Silicon perderías la ventaja de velocidad que es la
  razón de ser de esta elección.
- **Operaciones privilegiadas** (formatear, montar con `allow_other`) → un daemon
  separado (`NTFSHelper`) registrado vía `SMAppService` (disponible desde macOS 13,
  sin usar la API legacy `SMJobBless`). La app nunca ejecuta comandos de disco
  directamente; todo pasa por XPC al helper que corre como root.

## Rendimiento de transferencia

Las opciones de montaje en `HelperDelegate.mountNTFS` (`kernel_cache,auto_cache,
big_writes,blksize=1048576,noatime`) son la parte que más impacta la velocidad real:

- `kernel_cache` + `auto_cache`: deja que el kernel cachee páginas en vez de
  hacer un round-trip al daemon FUSE en cada lectura.
- `big_writes`: eleva el buffer de escritura muy por encima del límite viejo de
  4K de FUSE.
- `blksize=1048576`: bloques de 1 MB reducen drásticamente la cantidad de
  syscalls en transferencias secuenciales grandes (el caso típico de backups/medios).

Aun con esto, FUSE+ntfs-3g no va a igualar a un driver nativo en el kernel (que es
lo que realmente vende Paragon). Si en el futuro se necesita más velocidad, las
opciones son: (a) un driver NTFS comercial con licencia (Tuxera), o (b) escribir un
driver propio — ambas son inversiones de ingeniería serias, no algo incremental.

## Driver nativo (FSKit) — en progreso

`Sources/NTFSFSExtension/` arranca una segunda vía, paralela a la de FUSE/kext:
un módulo **FSKit** (el framework de Apple para filesystems de terceros en user
space, sin kext) que enlaza `libntfs-3g` **directo en el proceso de la
extensión** — sin el daemon FUSE, sin el hop extra de IPC que tiene macFUSE.
Es la única forma de que un filesystem de terceros en macOS se acerque al
rendimiento de un driver nativo sin escribir el parser de NTFS desde cero.

**Bloqueos reales antes de que esto corra, en orden:**

1. **`com.apple.developer.fskit.fsmodule` es un entitlement restringido.**
   Apple lo aprueba caso por caso vía perfil de aprovisionamiento — no es
   autoservicio como el resto de entitlements de este proyecto. Hay que
   solicitarlo en el portal de Apple Developer con una cuenta de pago antes
   de poder firmar y correr esto fuera de un entorno de desarrollo local.
2. **El target real se crea en Xcode, no a mano.** FSKit usa ExtensionKit
   (tecnología de appex moderna), y su Info.plist/entitlements wiring exacto
   no está en `project.yml` todavía a propósito — créalo con
   `File ▸ New ▸ Target ▸ macOS ▸ File System Extension` (Xcode 16.3+) y
   después reemplaza los archivos Swift que genere por los que ya están en
   `Sources/NTFSFSExtension/`.
3. **Varias firmas de API en `NTFSVolume.swift`/`NTFSEngine.swift` están
   marcadas `TODO`** (cómo se obtiene el BSD device path de un
   `FSBlockDeviceResource`, cómo se resuelve un `FSItem` a una ruta). FSKit es
   demasiado nuevo para confiar en nombres exactos sin el autocomplete real de
   Xcode — verifica esos puntos ahí antes de asumir que compila.

**Licenciamiento — esto cambia la exposición legal.** `ntfs-3g` es GPLv2. En
la app principal (`NTFSHelper`/macFUSE) solo se *invoca* el binario ya
instalado por el usuario — eso no genera obra derivada. En `NTFSFSExtension`,
en cambio, **se enlaza `libntfs-3g` directo en el binario de la extensión**
(decisión tomada a propósito por rendimiento). Eso sí convierte el binario de
esa extensión en obra derivada de GPLv2: si distribuyes `NTFSMate.app` con
esta extensión compilada adentro, estás obligado a liberar el código fuente
correspondiente de esa extensión bajo GPL (no necesariamente el resto de la
app, pero sí esa pieza). Resuelve esto con un abogado antes de notarizar o
distribuir un build que incluya `NTFSFSExtension`.

## Compilar

Requiere macOS Intel + Xcode. Este scaffold no se puede compilar ni probar desde
este contenedor Linux — fue escrito aquí, pero el build real debe hacerse en el Mac.

```sh
brew install xcodegen
./Scripts/install-dependencies.sh   # macFUSE + ntfs-3g
xcodegen generate
open NTFSMate.xcodeproj
```

Al compilar y correr por primera vez, macOS pedirá aprobar el daemon
`NTFSHelper` en Ajustes del Sistema > Privacidad y Seguridad.

## Qué falta para producción (no cubierto en este scaffold)

- Firma de código + notarización (obligatorio para que macFUSE y el helper
  carguen sin Gatekeeper bloqueando todo).
- UI de progreso real durante el formateo (`mkntfs` por ahora corre sin parseo
  de progreso).
- Manejo de desconexión abrupta durante escritura (unmount forzado / fsck).
- Tests. No hay ninguno todavía.
- Driver nativo FSKit: solicitud del entitlement restringido a Apple, crear el
  target real en Xcode, resolver los `TODO` de API marcados en
  `Sources/NTFSFSExtension/`, y la decisión legal de licenciamiento GPL antes
  de distribuirlo (ver sección "Driver nativo" arriba).
