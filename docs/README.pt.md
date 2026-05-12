# OpenBSD sshd + Google Authenticator (TOTP)

Autenticação de dois fatores para SSH no OpenBSD usando o Google Authenticator
(TOTP), com encaminhamento de registros de tentativas falhas para um servidor syslog remoto.

## Visão geral

Este repositório fornece:

| Arquivo | Finalidade |
|---------|-----------|
| `setup.sh` | Script de configuração automatizada — executar uma vez como root |
| `login_totp` | Backend BSD Auth que verifica o código TOTP |
| `google-authenticator-setup.sh` | Script de cadastro por usuário |
| `sshd_config.snippet` | Adições de referência para sshd_config |
| `syslog.conf.snippet` | Adições de referência para syslog.conf com encaminhamento remoto |

### Fluxo de autenticação

```
Cliente SSH
  │
  ▼
sshd  ──── 1. Autenticação por chave pública (par de chaves existente)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Prompt: "Google Authenticator code: "
  ├── 3. Usuário digita o TOTP de 6 dígitos do aplicativo
  ├── 4. oathtool verifica o código contra ~/.google_authenticator
  │
  ├─ SUCESSO → sessão aberta; auth.info registrado localmente + encaminhado
  └─ FALHA   → sessão encerrada; auth.warning registrado localmente + encaminhado
```

## Requisitos

- OpenBSD 7.x (testado nas versões 7.4 e 7.5)
- Acesso como root ou via `doas`
- Pacote `oath-toolkit` (`pkg_add oath-toolkit`) — fornece o `oathtool`
- Um servidor syslog remoto acessível a partir do host (rsyslog, syslog-ng, etc.)
- Os usuários devem ter uma chave pública SSH já instalada (`~/.ssh/authorized_keys`)

## Início rápido (automatizado)

```sh
doas sh setup.sh
```

O script irá:

1. Instalar `oath-toolkit` via `pkg_add`.
2. Copiar `login_totp` para `/usr/local/libexec/auth/login_totp`.
3. Adicionar a classe de login `totp` em `/etc/login.conf`.
4. Modificar `/etc/ssh/sshd_config`.
5. Modificar `/etc/syslog.conf` com regras de encaminhamento remoto.
6. Reiniciar `syslogd` e `sshd`.
7. Opcionalmente executar `google-authenticator-setup.sh` para cadastrar um usuário.

## Instalação manual

### 1. Instalar o oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Instalar o script de login BSD Auth

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Adicionar a classe de login `totp`

Adicionar o seguinte ao final de `/etc/login.conf`:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

Em seguida, reconstruir o banco de dados do login.conf:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Configurar o sshd

Adicionar as linhas de `sshd_config.snippet` a `/etc/ssh/sshd_config`.
As diretivas essenciais são:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Verificar e reiniciar o sshd:

```sh
doas sshd -t          # verificar configuração
doas rcctl restart sshd
```

### 5. Configurar o syslog remoto

Adicionar as linhas de `syslog.conf.snippet` a `/etc/syslog.conf`, substituindo
`REMOTE_SYSLOG_SERVER` pelo endereço real do servidor.

**UDP (padrão):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (mais confiável):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Para TCP, habilitar também o TCP em `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Recarregar o syslogd:

```sh
doas rcctl restart syslogd
```

### 6. Cadastrar usuários

Executar o script de cadastro por usuário (como root ou como o próprio usuário):

```sh
doas sh google-authenticator-setup.sh
```

O script:
1. Gera um segredo TOTP aleatório de 160 bits.
2. Grava em `~/.google_authenticator` (modo 0600).
3. Exibe uma URI `otpauth://` e um QR code no terminal (se `qrencode` estiver instalado).
4. Atribui o usuário à classe de login `totp`.

Escanear o QR code (ou colar a URI) no Google Authenticator, Aegis,
Authy ou qualquer aplicativo compatível com TOTP.

### 7. Atribuir usuários à classe de login totp

Se `google-authenticator-setup.sh` não foi utilizado, atribuir a classe manualmente:

```sh
doas usermod -L totp alice
```

## Verificando a configuração

### Testar o oathtool localmente

```sh
# Gerar o código TOTP atual para o segredo de um usuário:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Comparar este código com o exibido no aplicativo de autenticação — eles devem coincidir.

### Testar o encaminhamento do syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Verificar se essas mensagens chegam ao servidor syslog remoto.

### Testar o login SSH

Abrir uma **nova** sessão SSH (manter a sessão existente aberta caso seja necessário corrigir algo):

```sh
ssh -v alice@your-server
```

Fluxo esperado:
1. O sshd aceita a chave pública.
2. O prompt é exibido: `Google Authenticator code: `
3. Digitar o código de 6 dígitos do aplicativo de autenticação.
4. O login tem sucesso ou falha; o resultado aparece em `/var/log/authlog` e
   no servidor syslog remoto.

## Formato dos registros de falha de login

Quando `login_totp` rejeita um código TOTP, ele emite uma mensagem via `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Essa mensagem é gravada em:
- O syslog local (`/var/log/authlog` no OpenBSD).
- O servidor syslog remoto por meio da regra `auth.info` em `syslog.conf`.

Eventos adicionais de falha de autenticação são registrados pelo próprio sshd:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Referência de arquivos

### `login_totp` (backend BSD Auth)

- **Localização:** `/usr/local/libexec/auth/login_totp`
- **Permissões:** `root:auth 0550`
- **Arquivo de segredo:** `~/.google_authenticator` (primeira linha = segredo TOTP em base-32)
- **Registro:** `logger -p auth.warning` em caso de falha, `auth.info` em caso de sucesso
- **Tolerância de tempo:** ±1 × passo de 30 segundos (configurável via `TOTP_WINDOW`)

### `~/.google_authenticator`

Um arquivo de texto simples; a **primeira linha** deve ser o segredo TOTP em base-32.
Linhas adicionais (comentários) são ignoradas pelo `login_totp`.

Exemplo:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

As permissões devem ser `0600`, pertencentes ao usuário.

## Diferenças em relação ao FreeBSD / configurações baseadas em PAM

| Tópico | FreeBSD | OpenBSD |
|--------|---------|---------|
| Framework de autenticação | PAM (`pam_google_authenticator.so`) | BSD Auth (script `login_totp`) |
| Classe de login | n/a | Classe `totp` em `/etc/login.conf` |
| Pacote | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Daemon syslog | `syslogd` / `newsyslog` | `syslogd` (integrado) |
| Encaminhamento remoto UDP | `@host` em `syslog.conf` | `@host` em `syslog.conf` |
| Encaminhamento remoto TCP | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Solução de problemas

**"oathtool not found"**
Instalar o oath-toolkit: `doas pkg_add oath-toolkit`

**"No secret file for user"**
Executar `google-authenticator-setup.sh` para esse usuário, ou criar manualmente
`~/.google_authenticator` com o segredo em base-32 na primeira linha.

**Códigos TOTP sempre rejeitados**
Certifique-se de que o relógio do sistema está sincronizado (`ntpd` está habilitado no OpenBSD por
padrão). Uma diferença de horário superior a 30 segundos fará com que todos os códigos falhem.
Aumentar `TOTP_WINDOW` em `login_totp` se necessário.

**SSH pede senha em vez de código TOTP**
Verificar se `KbdInteractiveAuthentication yes` e
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` estão ambas
presentes em `/etc/ssh/sshd_config`, e se o usuário pertence à classe de login
`totp` (`doas usermod -L totp <user>`).

**sshd -t falha após editar sshd_config**
Executar `doas sshd -t` e corrigir os erros relatados antes de reiniciar o sshd.
O backup criado pelo `setup.sh` está em
`/etc/ssh/sshd_config.bak.<timestamp>`.

**O syslog remoto não está recebendo mensagens**
1. Confirmar que a porta UDP/TCP 514 do servidor remoto está acessível:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Verificar as regras de firewall em ambos os lados (OpenBSD pf e servidor remoto).
3. Para encaminhamento TCP, confirmar que `syslogd_flags="-T"` está em
   `/etc/rc.conf.local` e que o `syslogd` foi reiniciado.

## Licença

Licença BSD de 2 cláusulas. Consulte [LICENSE](../LICENSE) para mais detalhes.
