# OpenBSD sshd + Google Authenticator（TOTP）

使用 Google Authenticator（TOTP）為 OpenBSD SSH 提供雙重要素驗證，並將登入失敗日誌轉發至遠端 syslog 伺服器。

## 概覽

本存放庫提供以下檔案：

| 檔案 | 用途 |
|------|------|
| `setup.sh` | 自動化安裝腳本——以 root 身份執行一次 |
| `login_totp` | 驗證 TOTP 碼的 BSD Auth 後端 |
| `google-authenticator-setup.sh` | 針對個別使用者的註冊腳本 |
| `sshd_config.snippet` | sshd_config 設定參考片段 |
| `syslog.conf.snippet` | 用於遠端轉發的 syslog.conf 設定參考片段 |

### 驗證流程

```
SSH 用戶端
  │
  ▼
sshd  ──── 1. 公開金鑰驗證（現有金鑰對）
  │
  ▼
BSD Auth（login_totp）
  │
  ├── 2. 提示："Google Authenticator code: "
  ├── 3. 使用者從應用程式輸入 6 位 TOTP 碼
  ├── 4. oathtool 對照 ~/.google_authenticator 驗證該碼
  │
  ├─ 成功 → 工作階段開啟；auth.info 記錄至本地並轉發
  └─ 失敗 → 工作階段關閉；auth.warning 記錄至本地並轉發
```

## 系統需求

- OpenBSD 7.x（已在 7.4 及 7.5 上測試）
- root 或 `doas` 存取權限
- `oath-toolkit` 套件（`pkg_add oath-toolkit`）——提供 `oathtool`
- 主機可連線的遠端 syslog 伺服器（rsyslog、syslog-ng 等均可）
- 使用者必須已安裝 SSH 公開金鑰（`~/.ssh/authorized_keys`）

## 快速開始（自動化方式）

```sh
doas sh setup.sh
```

此腳本將：

1. 透過 `pkg_add` 安裝 `oath-toolkit`。
2. 將 `login_totp` 複製至 `/usr/local/libexec/auth/login_totp`。
3. 在 `/etc/login.conf` 中新增 `totp` 登入類別。
4. 修改 `/etc/ssh/sshd_config`。
5. 在 `/etc/syslog.conf` 中新增遠端轉發規則。
6. 重新啟動 `syslogd` 及 `sshd`。
7. 可選：執行 `google-authenticator-setup.sh` 為某位使用者完成註冊。

## 手動安裝

### 1. 安裝 oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. 安裝 BSD Auth 登入腳本

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. 新增 `totp` 登入類別

在 `/etc/login.conf` 末尾附加以下內容：

```
# TOTP（Google Authenticator）登入類別
totp:\
    :auth=-totp:\
    :tc=default:
```

然後重建 login.conf 資料庫：

```sh
doas cap_mkdb /etc/login.conf
```

### 4. 設定 sshd

將 `sshd_config.snippet` 中的內容新增至 `/etc/ssh/sshd_config`。
關鍵指令如下：

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

驗證並重新啟動 sshd：

```sh
doas sshd -t          # 驗證設定
doas rcctl restart sshd
```

### 5. 設定遠端 syslog

將 `syslog.conf.snippet` 中的內容新增至 `/etc/syslog.conf`，並將
`REMOTE_SYSLOG_SERVER` 替換為實際的伺服器位址。

**UDP（預設）：**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP（較為可靠）：**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

使用 TCP 時，還需在 `/etc/rc.conf.local` 中啟用 TCP：

```
syslogd_flags="-T"
```

重新載入 syslogd：

```sh
doas rcctl restart syslogd
```

### 6. 註冊使用者

以 root 身份或以使用者本身的身份執行單一使用者註冊腳本：

```sh
doas sh google-authenticator-setup.sh
```

此腳本將：
1. 產生一個隨機的 160 位元 TOTP 密鑰。
2. 將其寫入 `~/.google_authenticator`（權限 0600）。
3. 列印 `otpauth://` URI 及終端機 QR Code（若已安裝 `qrencode`）。
4. 將使用者指派至 `totp` 登入類別。

將 QR Code（或 URI）掃描或貼入 Google Authenticator、Aegis、
Authy 或任何相容 TOTP 的應用程式中。

### 7. 將使用者指派至 totp 登入類別

若未使用 `google-authenticator-setup.sh`，可手動指派登入類別：

```sh
doas usermod -L totp alice
```

## 驗證安裝

### 在本機測試 oathtool

```sh
# 為某使用者的密鑰產生目前的 TOTP 碼：
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

將此結果與驗證應用程式中顯示的碼進行比對——兩者應相符。

### 測試 syslog 轉發

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

確認這些訊息已送達遠端 syslog 伺服器。

### 測試 SSH 登入

開啟一個**新的** SSH 工作階段（保持現有工作階段開啟，以便在出現問題時修復）：

```sh
ssh -v alice@your-server
```

預期流程：
1. sshd 接受您的公開金鑰。
2. 出現提示：`Google Authenticator code: `
3. 輸入驗證應用程式中的 6 位碼。
4. 登入成功或失敗；結果將出現在 `/var/log/authlog` 以及遠端 syslog 伺服器上。

## 登入失敗日誌格式

當 `login_totp` 拒絕 TOTP 碼時，會透過 `logger(1)` 輸出一則訊息：

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

該訊息將寫入：
- 本地 syslog（OpenBSD 上為 `/var/log/authlog`）。
- 遠端 syslog 伺服器，透過 `syslog.conf` 中的 `auth.info` 規則。

sshd 本身還會記錄額外的驗證失敗事件：

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## 檔案參考

### `login_totp`（BSD Auth 後端）

- **位置：** `/usr/local/libexec/auth/login_totp`
- **權限：** `root:auth 0550`
- **密鑰檔案：** `~/.google_authenticator`（第一行 = base-32 TOTP 密鑰）
- **日誌：** 失敗時記錄 `logger -p auth.warning`，成功時記錄 `auth.info`
- **時間容差：** ±1 × 30 秒步長（可透過 `TOTP_WINDOW` 設定）

### `~/.google_authenticator`

一個純文字檔案；**第一行**必須是 base-32 TOTP 密鑰。
其餘行（注釋）將被 `login_totp` 忽略。

範例：
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

權限必須為 `0600`，擁有者為該使用者。

## 與 FreeBSD / 基於 PAM 方案的差異

| 主題 | FreeBSD | OpenBSD |
|------|---------|---------|
| 驗證框架 | PAM（`pam_google_authenticator.so`） | BSD Auth（`login_totp` 腳本） |
| 登入類別 | 不適用 | `/etc/login.conf` 中的 `totp` 類別 |
| 套件 | `security/google-authenticator-pam` | `security/oath-toolkit` |
| syslog 常駐程式 | `syslogd` / `newsyslog` | `syslogd`（內建） |
| 遠端 UDP 轉發 | `syslog.conf` 中的 `@host` | `syslog.conf` 中的 `@host` |
| 遠端 TCP 轉發 | `@@host` | `@@host`（+ `syslogd_flags="-T"`） |

## 疑難排解

**「oathtool not found」**
安裝 oath-toolkit：`doas pkg_add oath-toolkit`

**「No secret file for user」**
為該使用者執行 `google-authenticator-setup.sh`，或手動建立
`~/.google_authenticator` 並在第一行填寫 base-32 密鑰。

**TOTP 碼始終被拒絕**
確保系統時鐘已同步（OpenBSD 預設啟用 `ntpd`）。時鐘偏差超過 30 秒將導致所有碼驗證失敗。如有需要，可增大 `login_totp` 中的 `TOTP_WINDOW`。

**SSH 要求輸入密碼而非 TOTP 碼**
確認 `/etc/ssh/sshd_config` 中同時存在 `KbdInteractiveAuthentication yes` 及
`AuthenticationMethods publickey,keyboard-interactive:bsdauth`，且使用者已加入 `totp`
登入類別（`doas usermod -L totp <user>`）。

**編輯 sshd_config 後 sshd -t 失敗**
執行 `doas sshd -t` 並修復所有回報的錯誤，然後再重新啟動 sshd。
`setup.sh` 建立的備份位於
`/etc/ssh/sshd_config.bak.<timestamp>`。

**遠端 syslog 未收到訊息**
1. 確認遠端伺服器的 UDP/TCP 514 連接埠可連線：
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. 檢查兩端的防火牆規則（OpenBSD pf 及遠端伺服器）。
3. 使用 TCP 轉發時，確認 `/etc/rc.conf.local` 中有 `syslogd_flags="-T"` 且 `syslogd` 已重新啟動。

## 授權條款

BSD 2-Clause 授權條款。詳見 [LICENSE](../LICENSE)。
