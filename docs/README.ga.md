# OpenBSD sshd + Google Authenticator (TOTP)

Fíordheimhniú dhá chéim do OpenBSD SSH ag úsáid Google Authenticator
(TOTP), le logáil theipeanna logála in iúl chuig freastalaí syslog cianda.

## Forbhreathnú

Soláthraíonn an stór seo:

| Comhad | Cuspóir |
|--------|---------|
| `setup.sh` | Script suiteála uathoibrithe — rith uair amháin mar root |
| `login_totp` | Cúlchuid BSD Auth a fhíoraíonn an cód TOTP |
| `google-authenticator-setup.sh` | Script clárúcháin in aghaidh an úsáideora |
| `sshd_config.snippet` | Breiseanna tagartha sshd_config |
| `syslog.conf.snippet` | Breiseanna tagartha syslog.conf le haghaidh seachadta chianda |

### Sreabhadh fíordheimhnithe

```
Cliant SSH
  │
  ▼
sshd  ──── 1. Fíordheimhniú eochair phoiblí (péire eochairí atá ann)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Leid: "Google Authenticator code: "
  ├── 3. Cuireann an t-úsáideoir isteach TOTP 6 dhigit ón aip
  ├── 4. Fíoraíonn oathtool an cód in aghaidh ~/.google_authenticator
  │
  ├─ RATH → seisiún oscailte; auth.info logáilte go háitiúil + seachadta
  └─ TEIP → seisiún dúnta; auth.warning logáilte go háitiúil + seachadta
```

## Riachtanais

- OpenBSD 7.x (tástáilte ar 7.4 agus 7.5)
- Rochtain root nó `doas`
- Pacáiste `oath-toolkit` (`pkg_add oath-toolkit`) — soláthraíonn `oathtool`
- Freastalaí syslog cianda inrochtana ón óstach (rsyslog, syslog-ng, etc.)
- Ní mór d'úsáideoirí eochair phoiblí SSH a bheith suiteáilte acu (`~/.ssh/authorized_keys`)

## Tús tapa (uathoibrithe)

```sh
doas sh setup.sh
```

Déanfaidh an script:

1. `oath-toolkit` a shuiteáil trí `pkg_add`.
2. `login_totp` a chóipeáil go `/usr/local/libexec/auth/login_totp`.
3. Aicme logála `totp` a chur le `/etc/login.conf`.
4. `/etc/ssh/sshd_config` a phaistéail.
5. `/etc/syslog.conf` a phaistéail le rialacha seachadta cianda.
6. `syslogd` agus `sshd` a atosú.
7. `google-authenticator-setup.sh` a rith go roghnach chun úsáideoir a chlárú.

## Suiteáil de láimh

### 1. Suiteáil oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Suiteáil script logála BSD Auth

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Cuir leis an aicme logála `totp`

Cuir an méid seo a leanas le `/etc/login.conf`:

```
# Aicme logála TOTP (Google Authenticator)
totp:\
    :auth=-totp:\
    :tc=default:
```

Ansin atóg bunachar sonraí login.conf:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Cumraigh sshd

Cuir na línte ó `sshd_config.snippet` le `/etc/ssh/sshd_config`.
Is iad na treoracha criticiúla:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Fíoraigh agus atosú sshd:

```sh
doas sshd -t          # fíoraigh cumraíocht
doas rcctl restart sshd
```

### 5. Cumraigh syslog cianda

Cuir na línte ó `syslog.conf.snippet` le `/etc/syslog.conf`, ag ionadú
`REMOTE_SYSLOG_SERVER` le seoladh do fhreastalaí iarbhír.

**UDP (réamhshocrú):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (níos iontaofa):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Le haghaidh TCP, cumasaigh TCP freisin i `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Athlódáil syslogd:

```sh
doas rcctl restart syslogd
```

### 6. Clárú úsáideoirí

Rith an script clárúcháin in aghaidh an úsáideora (mar root nó mar an t-úsáideoir féin):

```sh
doas sh google-authenticator-setup.sh
```

An script:
1. Gineann rún TOTP randamach 160-giotán.
2. Scríobhann é chuig `~/.google_authenticator` (mód 0600).
3. Priontálann URI `otpauth://` agus cód QR teirminéil (má tá `qrencode` suiteáilte).
4. Sannaíonn an t-úsáideoir don aicme logála `totp`.

Scan an cód QR (nó greamaigh an URI) isteach i Google Authenticator, Aegis,
Authy, nó aon aip TOTP-chomhoiriúnach.

### 7. Sannaigh úsáideoirí don aicme logála totp

Mura ndearna tú `google-authenticator-setup.sh` a úsáid, sann an aicme de láimh:

```sh
doas usermod -L totp alice
```

## Fíorú an tsuiteála

### Tástáil oathtool go háitiúil

```sh
# Gin an cód TOTP reatha do rún úsáideora:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Cuir i gcomparáid é seo leis an gcód a thaispeántar san aip fíordheimhnithe — ba chóir go mbeadh siad mar an gcéanna.

### Tástáil seachadadh syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Seiceáil go dtagann na teachtaireachtaí seo ar an bhfreastalaí syslog cianda.

### Tástáil logáil isteach SSH

Oscail seisiún SSH **nua** (coinnigh do sheisiún reatha oscailte ar eagla
go dteastaíonn rud éigin a dheisiú):

```sh
ssh -v alice@your-server
```

Sreabhadh ionchais:
1. Glacann sshd le d'eochair phoiblí.
2. Feiceann tú an leid: `Google Authenticator code: `
3. Iontráil an cód 6 dhigit ón aip fíordheimhnithe.
4. Éiríonn nó teipeann an logáil isteach; feictear an toradh i `/var/log/authlog` agus
   ar an bhfreastalaí syslog cianda.

## Formáid logála theipeanna logála isteach

Nuair a dhiúltaíonn `login_totp` cód TOTP, seolann sé teachtaireacht trí `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Scríobhtar an teachtaireacht seo chuig:
- An syslog áitiúil (`/var/log/authlog` ar OpenBSD).
- An freastalaí syslog cianda trí riail `auth.info` i `syslog.conf`.

Logálann sshd féin imeachtaí teipe fíordheimhnithe breise:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Tagairt comhaid

### `login_totp` (cúlchuid BSD Auth)

- **Suíomh:** `/usr/local/libexec/auth/login_totp`
- **Ceadanna:** `root:auth 0550`
- **Comhad rúin:** `~/.google_authenticator` (chéad líne = rún TOTP base-32)
- **Logáil:** `logger -p auth.warning` ar theip, `auth.info` ar rath
- **Lamháil ama:** ±1 × céim 30 soicind (inchumraithe trí `TOTP_WINDOW`)

### `~/.google_authenticator`

Comhad gnáth-théacs; ní mór don **chéad líne** a bheith ina rún TOTP base-32.
Déanann `login_totp` neamhaird de línte breise (tuairimí).

Sampla:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Ní mór ceadanna `0600` a bheith ann, le húinéireacht ag an úsáideoir.

## Difríochtaí ó FreeBSD / suiteálacha bunaithe ar PAM

| Ábhar | FreeBSD | OpenBSD |
|-------|---------|---------|
| Creat fíordheimhnithe | PAM (`pam_google_authenticator.so`) | BSD Auth (script `login_totp`) |
| Aicme logála | n/a | `/etc/login.conf` aicme `totp` |
| Pacáiste | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Daemon syslog | `syslogd` / `newsyslog` | `syslogd` (tógtha isteach) |
| Seachadadh UDP cianda | `@host` i `syslog.conf` | `@host` i `syslog.conf` |
| Seachadadh TCP cianda | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Fabhtcheartú

**«oathtool not found»**
Suiteáil oath-toolkit: `doas pkg_add oath-toolkit`

**«No secret file for user»**
Rith `google-authenticator-setup.sh` don úsáideoir sin, nó cruthaigh
`~/.google_authenticator` de láimh le rún base-32 ar an gcéad líne.

**Cóid TOTP i gcónaí diúltaithe**
Cinntigh go bhfuil clog an chórais sioncrónaithe (`ntpd` cumasaithe ar OpenBSD de
réir réamhshocraithe). Beidh gach cód ag teip má tá sceabhadh cloig níos mó ná 30 soicind.
Méadaigh `TOTP_WINDOW` i `login_totp` más gá.

**Iarrann SSH pasfhocal in ionad cód TOTP**
Fíoraigh go bhfuil `KbdInteractiveAuthentication yes` agus
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` araon
i láthair i `/etc/ssh/sshd_config`, agus go bhfuil an t-úsáideoir san aicme logála `totp`
(`doas usermod -L totp <úsáideoir>`).

**Teipeann sshd -t tar éis sshd_config a chur in eagar**
Rith `doas sshd -t` agus deisigh earráidí tuairiscithe roimh sshd a atosú.
Tá an cúltaca a chruthaigh `setup.sh` ag
`/etc/ssh/sshd_config.bak.<stampa_ama>`.

**Syslog cianda gan teachtaireachtaí a fháil**
1. Deimhnigh go bhfuil port UDP/TCP 514 an fhreastalaí chianda inrochtana:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Seiceáil rialacha balla dóiteáin ar an dá thaobh (OpenBSD pf agus freastalaí cianda).
3. Le haghaidh seachadta TCP, deimhnigh go bhfuil `syslogd_flags="-T"` i
   `/etc/rc.conf.local` agus go bhfuil `syslogd` atosaithe.

## Ceadúnas

Ceadúnas BSD 2-Clásal. Féach [LICENSE](LICENSE) le haghaidh sonraí.
