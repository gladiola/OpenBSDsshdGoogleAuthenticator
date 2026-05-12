# OpenBSD sshd + Google Authenticator（TOTP）

使用 Google Authenticator（TOTP）为 OpenBSD SSH 提供双因素认证，并将登录失败日志转发至远程 syslog 服务器。

## 概述

本仓库提供以下文件：

| 文件 | 用途 |
|------|------|
| `setup.sh` | 自动化安装脚本——以 root 身份运行一次 |
| `login_totp` | 验证 TOTP 码的 BSD Auth 后端 |
| `google-authenticator-setup.sh` | 面向单个用户的注册脚本 |
| `sshd_config.snippet` | sshd_config 配置参考片段 |
| `syslog.conf.snippet` | 用于远程转发的 syslog.conf 配置参考片段 |

### 认证流程

```
SSH 客户端
  │
  ▼
sshd  ──── 1. 公钥认证（已有密钥对）
  │
  ▼
BSD Auth（login_totp）
  │
  ├── 2. 提示："Google Authenticator code: "
  ├── 3. 用户从应用中输入 6 位 TOTP 码
  ├── 4. oathtool 对照 ~/.google_authenticator 验证该码
  │
  ├─ 成功 → 会话开启；auth.info 记录至本地并转发
  └─ 失败 → 会话关闭；auth.warning 记录至本地并转发
```

## 系统要求

- OpenBSD 7.x（已在 7.4 和 7.5 上测试）
- root 或 `doas` 权限
- `oath-toolkit` 软件包（`pkg_add oath-toolkit`）——提供 `oathtool`
- 可从主机访问的远程 syslog 服务器（rsyslog、syslog-ng 等均可）
- 用户必须已安装 SSH 公钥（`~/.ssh/authorized_keys`）

## 快速开始（自动化方式）

```sh
doas sh setup.sh
```

该脚本将：

1. 通过 `pkg_add` 安装 `oath-toolkit`。
2. 将 `login_totp` 复制到 `/usr/local/libexec/auth/login_totp`。
3. 在 `/etc/login.conf` 中添加 `totp` 登录类。
4. 修改 `/etc/ssh/sshd_config`。
5. 在 `/etc/syslog.conf` 中添加远程转发规则。
6. 重启 `syslogd` 和 `sshd`。
7. 可选：运行 `google-authenticator-setup.sh` 为某个用户完成注册。

## 手动安装

### 1. 安装 oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. 安装 BSD Auth 登录脚本

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. 添加 `totp` 登录类

在 `/etc/login.conf` 末尾追加以下内容：

```
# TOTP（Google Authenticator）登录类
totp:\
    :auth=-totp:\
    :tc=default:
```

然后重建 login.conf 数据库：

```sh
doas cap_mkdb /etc/login.conf
```

### 4. 配置 sshd

将 `sshd_config.snippet` 中的内容添加到 `/etc/ssh/sshd_config`。
关键指令如下：

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

验证并重启 sshd：

```sh
doas sshd -t          # 验证配置
doas rcctl restart sshd
```

### 5. 配置远程 syslog

将 `syslog.conf.snippet` 中的内容添加到 `/etc/syslog.conf`，并将
`REMOTE_SYSLOG_SERVER` 替换为实际的服务器地址。

**UDP（默认）：**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP（更可靠）：**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

使用 TCP 时，还需在 `/etc/rc.conf.local` 中启用 TCP：

```
syslogd_flags="-T"
```

重新加载 syslogd：

```sh
doas rcctl restart syslogd
```

### 6. 注册用户

以 root 身份或以用户自身身份运行单用户注册脚本：

```sh
doas sh google-authenticator-setup.sh
```

该脚本将：
1. 生成一个随机的 160 位 TOTP 密钥。
2. 将其写入 `~/.google_authenticator`（权限 0600）。
3. 打印 `otpauth://` URI 以及终端二维码（若已安装 `qrencode`）。
4. 将用户分配到 `totp` 登录类。

将二维码（或 URI）扫描或粘贴到 Google Authenticator、Aegis、
Authy 或任何兼容 TOTP 的应用中。

### 7. 将用户分配到 totp 登录类

若未使用 `google-authenticator-setup.sh`，可手动分配登录类：

```sh
doas usermod -L totp alice
```

## 验证安装

### 在本地测试 oathtool

```sh
# 为某用户的密钥生成当前 TOTP 码：
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

将此结果与认证应用中显示的码进行对比——两者应一致。

### 测试 syslog 转发

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

确认这些消息已送达远程 syslog 服务器。

### 测试 SSH 登录

开启一个**新的** SSH 会话（保持现有会话打开，以便在出现问题时修复）：

```sh
ssh -v alice@your-server
```

预期流程：
1. sshd 接受您的公钥。
2. 出现提示：`Google Authenticator code: `
3. 输入认证应用中的 6 位码。
4. 登录成功或失败；结果将出现在 `/var/log/authlog` 以及远程 syslog 服务器上。

## 登录失败日志格式

当 `login_totp` 拒绝 TOTP 码时，会通过 `logger(1)` 输出一条消息：

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

该消息将写入：
- 本地 syslog（OpenBSD 上为 `/var/log/authlog`）。
- 远程 syslog 服务器，通过 `syslog.conf` 中的 `auth.info` 规则。

sshd 本身还会记录额外的认证失败事件：

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## 文件参考

### `login_totp`（BSD Auth 后端）

- **位置：** `/usr/local/libexec/auth/login_totp`
- **权限：** `root:auth 0550`
- **密钥文件：** `~/.google_authenticator`（第一行 = base-32 TOTP 密钥）
- **日志：** 失败时记录 `logger -p auth.warning`，成功时记录 `auth.info`
- **时间容差：** ±1 × 30 秒步长（可通过 `TOTP_WINDOW` 配置）

### `~/.google_authenticator`

一个纯文本文件；**第一行**必须是 base-32 TOTP 密钥。
其余行（注释）将被 `login_totp` 忽略。

示例：
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

权限必须为 `0600`，所有者为该用户。

## 与 FreeBSD / 基于 PAM 的方案的区别

| 主题 | FreeBSD | OpenBSD |
|------|---------|---------|
| 认证框架 | PAM（`pam_google_authenticator.so`） | BSD Auth（`login_totp` 脚本） |
| 登录类 | 不适用 | `/etc/login.conf` 中的 `totp` 类 |
| 软件包 | `security/google-authenticator-pam` | `security/oath-toolkit` |
| syslog 守护进程 | `syslogd` / `newsyslog` | `syslogd`（内置） |
| 远程 UDP 转发 | `syslog.conf` 中的 `@host` | `syslog.conf` 中的 `@host` |
| 远程 TCP 转发 | `@@host` | `@@host`（+ `syslogd_flags="-T"`） |

## 故障排除

**"oathtool not found"**
安装 oath-toolkit：`doas pkg_add oath-toolkit`

**"No secret file for user"**
为该用户运行 `google-authenticator-setup.sh`，或手动创建
`~/.google_authenticator` 并在第一行填写 base-32 密钥。

**TOTP 码始终被拒绝**
确保系统时钟已同步（OpenBSD 默认启用 `ntpd`）。时钟偏差超过 30 秒将导致所有码验证失败。如有需要，可增大 `login_totp` 中的 `TOTP_WINDOW`。

**SSH 要求输入密码而非 TOTP 码**
确认 `/etc/ssh/sshd_config` 中同时存在 `KbdInteractiveAuthentication yes` 和
`AuthenticationMethods publickey,keyboard-interactive:bsdauth`，且用户已加入 `totp`
登录类（`doas usermod -L totp <user>`）。

**编辑 sshd_config 后 sshd -t 失败**
运行 `doas sshd -t` 并修复所有报告的错误，然后再重启 sshd。
`setup.sh` 创建的备份位于
`/etc/ssh/sshd_config.bak.<timestamp>`。

**远程 syslog 未收到消息**
1. 确认远程服务器的 UDP/TCP 514 端口可达：
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. 检查双端的防火墙规则（OpenBSD pf 及远程服务器）。
3. 使用 TCP 转发时，确认 `/etc/rc.conf.local` 中有 `syslogd_flags="-T"` 且 `syslogd` 已重启。

## 许可证

BSD 2-Clause 许可证。详见 [LICENSE](../LICENSE)。
