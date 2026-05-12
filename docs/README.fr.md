# OpenBSD sshd + Google Authenticator (TOTP)

Authentification à deux facteurs pour SSH sur OpenBSD avec Google Authenticator
(TOTP), avec transmission des journaux d'échecs de connexion vers un serveur syslog distant.

## Présentation

Ce dépôt fournit :

| Fichier | Rôle |
|---------|------|
| `setup.sh` | Script de configuration automatisée — à exécuter une fois en tant que root |
| `login_totp` | Backend BSD Auth qui vérifie le code TOTP |
| `google-authenticator-setup.sh` | Script d'enrôlement par utilisateur |
| `sshd_config.snippet` | Ajouts de référence pour sshd_config |
| `syslog.conf.snippet` | Ajouts de référence pour syslog.conf avec transfert distant |

### Flux d'authentification

```
Client SSH
  │
  ▼
sshd  ──── 1. Authentification par clé publique (paire de clés existante)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Invite : "Google Authenticator code: "
  ├── 3. L'utilisateur saisit le TOTP à 6 chiffres depuis l'application
  ├── 4. oathtool vérifie le code contre ~/.google_authenticator
  │
  ├─ SUCCÈS → session ouverte ; auth.info journalisé localement + transmis
  └─ ÉCHEC  → session fermée ; auth.warning journalisé localement + transmis
```

## Prérequis

- OpenBSD 7.x (testé sur 7.4 et 7.5)
- Accès root ou via `doas`
- Paquet `oath-toolkit` (`pkg_add oath-toolkit`) — fournit `oathtool`
- Un serveur syslog distant joignable depuis l'hôte (rsyslog, syslog-ng, etc.)
- Les utilisateurs doivent avoir une clé publique SSH déjà installée (`~/.ssh/authorized_keys`)

## Démarrage rapide (automatisé)

```sh
doas sh setup.sh
```

Le script effectuera les opérations suivantes :

1. Installer `oath-toolkit` via `pkg_add`.
2. Copier `login_totp` vers `/usr/local/libexec/auth/login_totp`.
3. Ajouter une classe de connexion `totp` dans `/etc/login.conf`.
4. Modifier `/etc/ssh/sshd_config`.
5. Modifier `/etc/syslog.conf` avec les règles de transfert distant.
6. Redémarrer `syslogd` et `sshd`.
7. Exécuter optionnellement `google-authenticator-setup.sh` pour enrôler un utilisateur.

## Installation manuelle

### 1. Installer oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Installer le script de connexion BSD Auth

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Ajouter la classe de connexion `totp`

Ajouter ce qui suit à la fin de `/etc/login.conf` :

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

Puis reconstruire la base de données login.conf :

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Configurer sshd

Ajouter les lignes de `sshd_config.snippet` à `/etc/ssh/sshd_config`.
Les directives essentielles sont :

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Vérifier et redémarrer sshd :

```sh
doas sshd -t          # vérifier la configuration
doas rcctl restart sshd
```

### 5. Configurer le syslog distant

Ajouter les lignes de `syslog.conf.snippet` à `/etc/syslog.conf`, en remplaçant
`REMOTE_SYSLOG_SERVER` par l'adresse réelle du serveur.

**UDP (par défaut) :**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (plus fiable) :**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Pour TCP, activer également TCP dans `/etc/rc.conf.local` :

```
syslogd_flags="-T"
```

Recharger syslogd :

```sh
doas rcctl restart syslogd
```

### 6. Enrôler les utilisateurs

Exécuter le script d'enrôlement par utilisateur (en tant que root ou en tant que l'utilisateur lui-même) :

```sh
doas sh google-authenticator-setup.sh
```

Le script :
1. Génère un secret TOTP aléatoire de 160 bits.
2. L'écrit dans `~/.google_authenticator` (mode 0600).
3. Affiche une URI `otpauth://` et un QR code dans le terminal (si `qrencode` est installé).
4. Affecte l'utilisateur à la classe de connexion `totp`.

Scanner le QR code (ou coller l'URI) dans Google Authenticator, Aegis,
Authy ou toute application compatible TOTP.

### 7. Affecter les utilisateurs à la classe de connexion totp

Si `google-authenticator-setup.sh` n'a pas été utilisé, affecter la classe manuellement :

```sh
doas usermod -L totp alice
```

## Vérification de la configuration

### Tester oathtool localement

```sh
# Générer le code TOTP actuel pour le secret d'un utilisateur :
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Comparer ce code avec celui affiché dans l'application d'authentification — ils doivent correspondre.

### Tester le transfert syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Vérifier que ces messages arrivent bien sur le serveur syslog distant.

### Tester la connexion SSH

Ouvrir une **nouvelle** session SSH (garder la session existante ouverte en cas de problème à corriger) :

```sh
ssh -v alice@your-server
```

Déroulement attendu :
1. sshd accepte la clé publique.
2. L'invite apparaît : `Google Authenticator code: `
3. Saisir le code à 6 chiffres depuis l'application d'authentification.
4. La connexion réussit ou échoue ; le résultat apparaît dans `/var/log/authlog` et
   sur le serveur syslog distant.

## Format des journaux d'échecs de connexion

Lorsque `login_totp` rejette un code TOTP, il émet un message via `logger(1)` :

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Ce message est écrit dans :
- Le syslog local (`/var/log/authlog` sur OpenBSD).
- Le serveur syslog distant via la règle `auth.info` dans `syslog.conf`.

Les autres événements d'authentification échouée sont journalisés par sshd lui-même :

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Référence des fichiers

### `login_totp` (backend BSD Auth)

- **Emplacement :** `/usr/local/libexec/auth/login_totp`
- **Permissions :** `root:auth 0550`
- **Fichier secret :** `~/.google_authenticator` (première ligne = secret TOTP en base-32)
- **Journalisation :** `logger -p auth.warning` en cas d'échec, `auth.info` en cas de succès
- **Tolérance temporelle :** ±1 × pas de 30 secondes (configurable via `TOTP_WINDOW`)

### `~/.google_authenticator`

Un fichier texte brut ; la **première ligne** doit être le secret TOTP en base-32.
Les lignes supplémentaires (commentaires) sont ignorées par `login_totp`.

Exemple :
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Les permissions doivent être `0600`, appartenant à l'utilisateur concerné.

## Différences avec FreeBSD / les configurations basées sur PAM

| Sujet | FreeBSD | OpenBSD |
|-------|---------|---------|
| Framework d'authentification | PAM (`pam_google_authenticator.so`) | BSD Auth (script `login_totp`) |
| Classe de connexion | n/a | Classe `totp` dans `/etc/login.conf` |
| Paquet | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Démon syslog | `syslogd` / `newsyslog` | `syslogd` (intégré) |
| Transfert distant UDP | `@host` dans `syslog.conf` | `@host` dans `syslog.conf` |
| Transfert distant TCP | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Dépannage

**« oathtool not found »**
Installer oath-toolkit : `doas pkg_add oath-toolkit`

**« No secret file for user »**
Exécuter `google-authenticator-setup.sh` pour cet utilisateur, ou créer manuellement
`~/.google_authenticator` avec le secret en base-32 sur la première ligne.

**Les codes TOTP sont toujours rejetés**
S'assurer que l'horloge système est synchronisée (`ntpd` est activé par défaut sur OpenBSD).
Un décalage d'horloge supérieur à 30 secondes entraînera l'échec de tous les codes.
Augmenter `TOTP_WINDOW` dans `login_totp` si nécessaire.

**SSH demande un mot de passe au lieu d'un code TOTP**
Vérifier que `KbdInteractiveAuthentication yes` et
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` sont tous deux
présents dans `/etc/ssh/sshd_config`, et que l'utilisateur appartient à la classe de connexion
`totp` (`doas usermod -L totp <user>`).

**sshd -t échoue après modification de sshd_config**
Exécuter `doas sshd -t` et corriger toutes les erreurs signalées avant de redémarrer sshd.
La sauvegarde créée par `setup.sh` se trouve à l'emplacement
`/etc/ssh/sshd_config.bak.<timestamp>`.

**Le syslog distant ne reçoit pas les messages**
1. Confirmer que le port UDP/TCP 514 du serveur distant est joignable :
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Vérifier les règles de pare-feu des deux côtés (OpenBSD pf et serveur distant).
3. Pour le transfert TCP, confirmer que `syslogd_flags="-T"` figure dans
   `/etc/rc.conf.local` et que `syslogd` a été redémarré.

## Licence

Licence BSD à 2 clauses. Voir [LICENSE](../LICENSE) pour les détails.
