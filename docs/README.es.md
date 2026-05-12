# OpenBSD sshd + Google Authenticator (TOTP)

Autenticación de dos factores para SSH en OpenBSD mediante Google Authenticator
(TOTP), con reenvío de registros de intentos fallidos a un servidor syslog remoto.

## Descripción general

Este repositorio proporciona:

| Archivo | Propósito |
|---------|-----------|
| `setup.sh` | Script de configuración automatizada — ejecutar una vez como root |
| `login_totp` | Backend BSD Auth que verifica el código TOTP |
| `google-authenticator-setup.sh` | Script de registro por usuario |
| `sshd_config.snippet` | Adiciones de referencia para sshd_config |
| `syslog.conf.snippet` | Adiciones de referencia para syslog.conf con reenvío remoto |

### Flujo de autenticación

```
Cliente SSH
  │
  ▼
sshd  ──── 1. Autenticación por clave pública (par de claves existente)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Solicitud: "Google Authenticator code: "
  ├── 3. El usuario introduce el TOTP de 6 dígitos desde la app
  ├── 4. oathtool verifica el código contra ~/.google_authenticator
  │
  ├─ ÉXITO  → sesión abierta; auth.info registrado localmente + reenviado
  └─ FALLO  → sesión cerrada; auth.warning registrado localmente + reenviado
```

## Requisitos

- OpenBSD 7.x (probado en 7.4 y 7.5)
- Acceso como root o mediante `doas`
- Paquete `oath-toolkit` (`pkg_add oath-toolkit`) — proporciona `oathtool`
- Un servidor syslog remoto accesible desde el host (rsyslog, syslog-ng, etc.)
- Los usuarios deben tener una clave pública SSH ya instalada (`~/.ssh/authorized_keys`)

## Inicio rápido (automatizado)

```sh
doas sh setup.sh
```

El script realizará los siguientes pasos:

1. Instalar `oath-toolkit` mediante `pkg_add`.
2. Copiar `login_totp` a `/usr/local/libexec/auth/login_totp`.
3. Añadir una clase de inicio de sesión `totp` en `/etc/login.conf`.
4. Modificar `/etc/ssh/sshd_config`.
5. Modificar `/etc/syslog.conf` con reglas de reenvío remoto.
6. Reiniciar `syslogd` y `sshd`.
7. Opcionalmente ejecutar `google-authenticator-setup.sh` para registrar un usuario.

## Instalación manual

### 1. Instalar oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Instalar el script de inicio de sesión BSD Auth

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Añadir la clase de inicio de sesión `totp`

Añadir lo siguiente al final de `/etc/login.conf`:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

Luego reconstruir la base de datos de login.conf:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Configurar sshd

Añadir las líneas de `sshd_config.snippet` a `/etc/ssh/sshd_config`.
Las directivas esenciales son:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Verificar y reiniciar sshd:

```sh
doas sshd -t          # verificar configuración
doas rcctl restart sshd
```

### 5. Configurar syslog remoto

Añadir las líneas de `syslog.conf.snippet` a `/etc/syslog.conf`, reemplazando
`REMOTE_SYSLOG_SERVER` con la dirección real del servidor.

**UDP (predeterminado):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (más fiable):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Para TCP, también activar TCP en `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Recargar syslogd:

```sh
doas rcctl restart syslogd
```

### 6. Registrar usuarios

Ejecutar el script de registro por usuario (como root o como el propio usuario):

```sh
doas sh google-authenticator-setup.sh
```

El script:
1. Genera un secreto TOTP aleatorio de 160 bits.
2. Lo escribe en `~/.google_authenticator` (modo 0600).
3. Imprime una URI `otpauth://` y un código QR en la terminal (si `qrencode` está instalado).
4. Asigna al usuario a la clase de inicio de sesión `totp`.

Escanear el código QR (o pegar la URI) en Google Authenticator, Aegis,
Authy o cualquier app compatible con TOTP.

### 7. Asignar usuarios a la clase de inicio de sesión totp

Si no se utilizó `google-authenticator-setup.sh`, asignar la clase manualmente:

```sh
doas usermod -L totp alice
```

## Verificación de la configuración

### Probar oathtool localmente

```sh
# Generar el código TOTP actual para el secreto de un usuario:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Comparar este código con el que muestra la app de autenticación — deben coincidir.

### Probar el reenvío de syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Verificar que estos mensajes llegan al servidor syslog remoto.

### Probar el inicio de sesión SSH

Abrir una **nueva** sesión SSH (mantener la sesión existente abierta por si hay que corregir algo):

```sh
ssh -v alice@your-server
```

Flujo esperado:
1. sshd acepta la clave pública.
2. Aparece la solicitud: `Google Authenticator code: `
3. Introducir el código de 6 dígitos de la app de autenticación.
4. El inicio de sesión tiene éxito o falla; el resultado aparece en `/var/log/authlog` y
   en el servidor syslog remoto.

## Formato de los registros de fallos de inicio de sesión

Cuando `login_totp` rechaza un código TOTP, emite un mensaje mediante `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Este mensaje se escribe en:
- El syslog local (`/var/log/authlog` en OpenBSD).
- El servidor syslog remoto mediante la regla `auth.info` en `syslog.conf`.

Los eventos adicionales de autenticación fallida son registrados por el propio sshd:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Referencia de archivos

### `login_totp` (backend BSD Auth)

- **Ubicación:** `/usr/local/libexec/auth/login_totp`
- **Permisos:** `root:auth 0550`
- **Archivo de secreto:** `~/.google_authenticator` (primera línea = secreto TOTP en base-32)
- **Registro:** `logger -p auth.warning` en caso de fallo, `auth.info` en caso de éxito
- **Tolerancia de tiempo:** ±1 × paso de 30 segundos (configurable mediante `TOTP_WINDOW`)

### `~/.google_authenticator`

Un archivo de texto plano; la **primera línea** debe ser el secreto TOTP en base-32.
Las líneas adicionales (comentarios) son ignoradas por `login_totp`.

Ejemplo:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Los permisos deben ser `0600`, propiedad del usuario.

## Diferencias respecto a FreeBSD / configuraciones basadas en PAM

| Aspecto | FreeBSD | OpenBSD |
|---------|---------|---------|
| Marco de autenticación | PAM (`pam_google_authenticator.so`) | BSD Auth (script `login_totp`) |
| Clase de inicio de sesión | n/a | Clase `totp` en `/etc/login.conf` |
| Paquete | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Demonio syslog | `syslogd` / `newsyslog` | `syslogd` (integrado) |
| Reenvío remoto UDP | `@host` en `syslog.conf` | `@host` en `syslog.conf` |
| Reenvío remoto TCP | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Solución de problemas

**"oathtool not found"**
Instalar oath-toolkit: `doas pkg_add oath-toolkit`

**"No secret file for user"**
Ejecutar `google-authenticator-setup.sh` para ese usuario, o crear manualmente
`~/.google_authenticator` con el secreto en base-32 en la primera línea.

**Los códigos TOTP siempre son rechazados**
Asegurarse de que el reloj del sistema está sincronizado (`ntpd` está activado en OpenBSD por
defecto). Una desviación del reloj superior a 30 segundos hará que todos los códigos fallen.
Aumentar `TOTP_WINDOW` en `login_totp` si es necesario.

**SSH solicita una contraseña en lugar de un código TOTP**
Verificar que `KbdInteractiveAuthentication yes` y
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` están ambas
presentes en `/etc/ssh/sshd_config`, y que el usuario pertenece a la clase de inicio de sesión
`totp` (`doas usermod -L totp <user>`).

**sshd -t falla después de editar sshd_config**
Ejecutar `doas sshd -t` y corregir los errores reportados antes de reiniciar sshd.
La copia de seguridad creada por `setup.sh` se encuentra en
`/etc/ssh/sshd_config.bak.<timestamp>`.

**El syslog remoto no recibe mensajes**
1. Confirmar que el puerto UDP/TCP 514 del servidor remoto es accesible:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Revisar las reglas del cortafuegos en ambos extremos (OpenBSD pf y servidor remoto).
3. Para el reenvío TCP, confirmar que `syslogd_flags="-T"` está en
   `/etc/rc.conf.local` y que `syslogd` ha sido reiniciado.

## Licencia

Licencia BSD de 2 cláusulas. Consultar [LICENSE](../LICENSE) para más detalles.
