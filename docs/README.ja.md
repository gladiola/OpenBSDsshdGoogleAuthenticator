# OpenBSD sshd + Google Authenticator (TOTP)

Google Authenticator（TOTP）を使用した OpenBSD SSH の二要素認証。
失敗したログインのログはリモート syslog サーバーに転送されます。

## 概要

このリポジトリが提供するもの：

| ファイル | 目的 |
|------|---------|
| `setup.sh` | 自動セットアップスクリプト — root として一度実行する |
| `login_totp` | TOTP コードを検証する BSD Auth バックエンド |
| `google-authenticator-setup.sh` | ユーザーごとの登録スクリプト |
| `sshd_config.snippet` | 参照用 sshd_config 追記内容 |
| `syslog.conf.snippet` | リモート転送用の参照 syslog.conf 追記内容 |

### 認証フロー

```
SSH クライアント
  │
  ▼
sshd  ──── 1. 公開鍵認証（既存の鍵ペア）
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. プロンプト: "Google Authenticator code: "
  ├── 3. ユーザーがアプリから 6 桁の TOTP を入力
  ├── 4. oathtool が ~/.google_authenticator に対してコードを検証
  │
  ├─ 成功 → セッション開始；auth.info がローカルに記録され転送される
  └─ 失敗 → セッション終了；auth.warning がローカルに記録され転送される
```

## 必要条件

- OpenBSD 7.x（7.4 および 7.5 でテスト済み）
- root または `doas` アクセス
- `oath-toolkit` パッケージ（`pkg_add oath-toolkit`）— `oathtool` を提供
- ホストから到達可能なリモート syslog サーバー（rsyslog、syslog-ng など）
- ユーザーは SSH 公開鍵がインストール済みであること（`~/.ssh/authorized_keys`）

## クイックスタート（自動）

```sh
doas sh setup.sh
```

スクリプトは以下を実行します：

1. `pkg_add` 経由で `oath-toolkit` をインストール。
2. `login_totp` を `/usr/local/libexec/auth/login_totp` にコピー。
3. `/etc/login.conf` に `totp` ログインクラスを追加。
4. `/etc/ssh/sshd_config` にパッチを適用。
5. `/etc/syslog.conf` にリモート転送ルールを追加。
6. `syslogd` と `sshd` を再起動。
7. オプションで `google-authenticator-setup.sh` を実行してユーザーを登録。

## 手動インストール

### 1. oath-toolkit のインストール

```sh
doas pkg_add oath-toolkit
```

### 2. BSD Auth ログインスクリプトのインストール

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. `totp` ログインクラスの追加

`/etc/login.conf` に以下を追記します：

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

次に login.conf データベースを再構築します：

```sh
doas cap_mkdb /etc/login.conf
```

### 4. sshd の設定

`sshd_config.snippet` の内容を `/etc/ssh/sshd_config` に追加します。
重要なディレクティブは以下の通りです：

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

sshd を検証して再起動します：

```sh
doas sshd -t          # 設定を検証
doas rcctl restart sshd
```

### 5. リモート syslog の設定

`syslog.conf.snippet` の内容を `/etc/syslog.conf` に追加し、
`REMOTE_SYSLOG_SERVER` を実際のサーバーアドレスに置き換えます。

**UDP（デフォルト）：**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP（より信頼性が高い）：**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

TCP の場合、`/etc/rc.conf.local` で TCP を有効化します：

```
syslogd_flags="-T"
```

syslogd を再読み込みします：

```sh
doas rcctl restart syslogd
```

### 6. ユーザーの登録

ユーザーごとの登録スクリプトを実行します（root またはユーザー自身として）：

```sh
doas sh google-authenticator-setup.sh
```

スクリプトの動作：
1. ランダムな 160 ビット TOTP シークレットを生成。
2. `~/.google_authenticator`（モード 0600）に書き込む。
3. `otpauth://` URI とターミナル QR コードを表示（`qrencode` がインストールされている場合）。
4. ユーザーを `totp` ログインクラスに割り当てる。

QR コードをスキャン（または URI を貼り付け）して、Google Authenticator、Aegis、
Authy、または TOTP 対応アプリに登録します。

### 7. ユーザーを totp ログインクラスに割り当てる

`google-authenticator-setup.sh` を使用しなかった場合は、手動でクラスを割り当てます：

```sh
doas usermod -L totp alice
```

## セットアップの確認

### oathtool をローカルでテスト

```sh
# ユーザーのシークレットで現在の TOTP コードを生成：
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

認証アプリに表示されるコードと比較してください — 一致するはずです。

### syslog 転送のテスト

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

これらのメッセージがリモート syslog サーバーに届くことを確認します。

### SSH ログインのテスト

**新しい** SSH セッションを開きます（問題が発生した場合に備えて既存のセッションは開いたままにする）：

```sh
ssh -v alice@your-server
```

期待されるフロー：
1. sshd が公開鍵を受け入れる。
2. プロンプトが表示される：`Google Authenticator code: `
3. 認証アプリから 6 桁のコードを入力。
4. ログインが成功または失敗し、結果が `/var/log/authlog` と
   リモート syslog サーバーに表示される。

## ログイン失敗時のログ形式

`login_totp` が TOTP コードを拒否すると、`logger(1)` を通じてメッセージを出力します：

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

このメッセージは以下に書き込まれます：
- ローカル syslog（OpenBSD では `/var/log/authlog`）。
- `syslog.conf` の `auth.info` ルールを介してリモート syslog サーバー。

追加の認証失敗イベントは sshd 自身によって記録されます：

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## ファイルリファレンス

### `login_totp`（BSD Auth バックエンド）

- **場所：** `/usr/local/libexec/auth/login_totp`
- **パーミッション：** `root:auth 0550`
- **シークレットファイル：** `~/.google_authenticator`（1 行目 = base-32 TOTP シークレット）
- **ログ：** 失敗時は `logger -p auth.warning`、成功時は `auth.info`
- **時刻許容範囲：** ±1 × 30 秒ステップ（`TOTP_WINDOW` で設定可能）

### `~/.google_authenticator`

プレーンテキストファイル；**1 行目**は base-32 TOTP シークレットでなければなりません。
追加の行（コメント）は `login_totp` によって無視されます。

例：
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

パーミッションは `0600` で、ユーザーが所有者である必要があります。

## FreeBSD / PAM ベースのセットアップとの違い

| 項目 | FreeBSD | OpenBSD |
|-------|---------|---------|
| 認証フレームワーク | PAM (`pam_google_authenticator.so`) | BSD Auth (`login_totp` スクリプト) |
| ログインクラス | なし | `/etc/login.conf` `totp` クラス |
| パッケージ | `security/google-authenticator-pam` | `security/oath-toolkit` |
| syslog デーモン | `syslogd` / `newsyslog` | `syslogd`（組み込み） |
| リモート UDP 転送 | `syslog.conf` の `@host` | `syslog.conf` の `@host` |
| リモート TCP 転送 | `@@host` | `@@host`（+ `syslogd_flags="-T"`） |

## トラブルシューティング

**"oathtool not found"**
oath-toolkit をインストールしてください：`doas pkg_add oath-toolkit`

**"No secret file for user"**
そのユーザーに対して `google-authenticator-setup.sh` を実行するか、
base-32 シークレットを 1 行目に記載した `~/.google_authenticator` を手動で作成してください。

**TOTP コードが常に拒否される**
システムクロックが同期されていることを確認してください（OpenBSD では `ntpd` がデフォルトで有効）。
30 秒を超えるクロックのずれがあると、すべてのコードが失敗します。
必要に応じて `login_totp` の `TOTP_WINDOW` を増やしてください。

**SSH が TOTP コードではなくパスワードを要求する**
`KbdInteractiveAuthentication yes` と
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` の両方が
`/etc/ssh/sshd_config` に存在すること、およびユーザーが `totp` ログインクラスに
含まれていることを確認してください（`doas usermod -L totp <user>`）。

**sshd_config 編集後に sshd -t が失敗する**
`doas sshd -t` を実行し、sshd を再起動する前に報告されたエラーを修正してください。
`setup.sh` が作成したバックアップは
`/etc/ssh/sshd_config.bak.<timestamp>` にあります。

**リモート syslog がメッセージを受信しない**
1. リモートサーバーの UDP/TCP ポート 514 に到達可能か確認：
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. 両端のファイアウォールルールを確認（OpenBSD pf とリモートサーバー）。
3. TCP 転送の場合、`syslogd_flags="-T"` が `/etc/rc.conf.local` にあり、
   `syslogd` が再起動されていることを確認してください。

## ライセンス

BSD 2-Clause ライセンス。詳細は [LICENSE](../LICENSE) を参照してください。
