# NTFSMate

Utilidad de barra de menú para macOS (Intel) que detecta USBs al instante,
formatea como NTFS y monta con lectura/escritura a la máxima velocidad que
permite el stack open-source disponible en macOS.

**Target declarado: macOS Ventura (13.0) en adelante** — cubre Ventura, Sonoma,
Sequoia y Tahoe con el mismo build. La arquitectura (FUSE/kext +
`SMAppService`, disponible desde macOS 13) no usa ninguna API exclusiva de
una versión más nueva, así que no hace falta mantener builds separados por OS.

**Uso: personal, no comercial, sin cuenta de pago.** Esto no se va a distribuir
a terceros, solo corre en la(s) Mac del propio desarrollador. Por eso la
arquitectura es macFUSE + `ntfs-3g` (no FSKit nativo): macFUSE ya viene firmado
y notarizado por su propio desarrollador — se instala vía Homebrew, no hay que
firmarlo nosotros. Para `NTFSMate.app`/`NTFSHelper` alcanza con un Apple ID
gratuito (firma de desarrollo local en Xcode); no se necesita cuenta de pago
ni entitlements restringidos. (Se evaluó un driver nativo vía FSKit, pero
requiere el entitlement restringido `com.apple.developer.fskit.fsmodule`, que
Apple solo otorga con cuenta de pago — se descartó por eso; ver el historial
de commits de este repo si se quiere retomar más adelante.)

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

## Compilar

Requiere macOS Intel + Xcode. Este scaffold no se puede compilar ni probar desde
este contenedor Linux — fue escrito aquí, pero el build real debe hacerse en el Mac.

### 1. Clonar e instalar dependencias

```sh
git clone -b claude/vibrant-maxwell-xw0bpd https://github.com/eddyvlz001/ntfs.git
cd ntfs
./Scripts/install-dependencies.sh   # macFUSE + ntfs-3g
```

Apple bloquea el kext de macFUSE la primera vez — es normal: ve a
**Ajustes del Sistema → Privacidad y Seguridad**, busca el aviso de software
de un desarrollador bloqueado y dale **Permitir**. Puede pedir reiniciar.

### 2. Generar y abrir el proyecto

```sh
brew install xcodegen
xcodegen generate
open NTFSMate.xcodeproj
```

### 3. Firmar con tu Apple ID gratuito

En Xcode, para **ambos** targets (`NTFSMate` y `NTFSHelper`) en
*Signing & Capabilities*: marca "Automatically manage signing" y elige tu
Apple ID como Team (si no aparece, agrégalo en Xcode → Settings → Accounts;
se crea un "Personal Team" sin costo). **Los dos targets deben quedar con el
mismo Team ID** — es requisito de `SMAppService` para que reconozca al helper
como del mismo desarrollador que la app.

### 4. Compilar y correr

`Cmd+R`. Al registrar el helper privilegiado por primera vez, macOS pedirá
aprobarlo en Ajustes del Sistema > Privacidad y Seguridad.

### 5. Probar con una USB real

Conéctala — debe aparecer de inmediato en el popover de la barra de menú. Si
no tiene NTFS, aparece el botón "Formatear como NTFS"; si ya lo es, se monta
sola.

### 6. Medir velocidad real

Con la unidad montada en `/Volumes/<nombre>`:

```sh
# Escritura
dd if=/dev/zero of=/Volumes/<nombre>/test.bin bs=1m count=2048

# Lectura (usa un archivo bastante más grande que tu RAM para que no lo
# sirva desde caché)
dd if=/Volumes/<nombre>/test.bin of=/dev/null bs=1m
```

Los MB/s que reporte cada `dd` al final son el número real contra el que hay
que comparar cualquier requisito de velocidad mínima.

## Qué falta para producción (no cubierto en este scaffold)

- Firma de código local con tu Apple ID gratuito (Xcode > Signing & Capabilities
  > Personal Team). No se necesita notarización para uso solo-personal; esa
  solo hace falta si algún día lo instalas en una Mac que no sea la tuya.
- UI de progreso real durante el formateo (`mkntfs` por ahora corre sin parseo
  de progreso).
- Manejo de desconexión abrupta durante escritura (unmount forzado / fsck).
- Tests. No hay ninguno todavía.
