# Codex Usage App

<p align="center">
  <img src="Resources/AppIcon.svg" width="128" alt="Codex Usage Appのアイコン">
</p>

Codexの5時間枠と週次枠の残量をmacOSのメニューバーへ表示する、非公式の
オープンソースアプリです。

[English README](README.md)

<p align="center">
  <a href="https://github.com/estay-inc/codex-usage-app/releases/latest/download/Codex-Usage-App.dmg"><strong>macOS版をダウンロード（DMG）</strong></a>
</p>

## 機能

- メニューバーに5時間枠（`5h`）と週次枠（`W`）の残量を表示
- 使用率、リセット日時、契約プラン、最終更新時刻を表示
- 2分ごとに自動更新
- macOS標準の`SMAppService`によるログイン時起動
- macOSの言語設定に合わせて日本語・英語の表示を自動切り替え
- 解析ツールや開発者サーバーを使用せず、Usage値を外部保存しない

## 動作条件

- macOS 13以降
- Apple SiliconまたはIntel Mac
- 以下のいずれかがインストールされ、ログイン済みであること
  - ChatGPT/Codexデスクトップアプリ
  - Codex CLI

このアプリはローカルの[Codex App Server](https://learn.chatgpt.com/docs/app-server)
を起動し、公式仕様の`account/rateLimits/read`を呼び出します。ChatGPTの
トークンを直接読み取ったり保存したりすることはありません。

## リリース版のインストール

1. [Codex-Usage-App.dmg](https://github.com/estay-inc/codex-usage-app/releases/latest/download/Codex-Usage-App.dmg)をダウンロードして開きます。
2. DMGを開き、その中の`Codex Usage.app`を開きます。
3. 「Applicationsフォルダへ移動しますか？」の画面で「移動して開く」を
   クリックします。
4. macOSにブロックされた場合は、FinderでControlキーを押しながらアプリを
   クリックし、「開く」を一度選択してください。
5. 必要に応じて、メニューから「ログイン時に起動」を有効にします。

コミュニティ向けリリースはAd Hoc署名であり、Appleの公証は受けていません。

## ソースからビルド

Xcode本体は必須ではありません。Xcode Command Line ToolsのSwiftツール
チェーンでビルドできます。

```bash
git clone https://github.com/estay-inc/codex-usage-app.git
cd codex-usage-app
./scripts/build.sh
open "build/Codex Usage.app"
```

Universal BinaryとZIPを作成する場合：

```bash
ARCHS=universal PACKAGE=1 ./scripts/build.sh
```

GitHub Releases用のDMGを作成する場合：

```bash
ARCHS=universal DMG=1 ./scripts/build.sh
```

Codexへログイン済みのMacで実データ取得までテストする場合：

```bash
CODEX_USAGE_LIVE_TEST=1 ./scripts/test.sh
```

Codexが独自の場所にある場合は、起動前に`CODEX_PATH`へ実行ファイルの絶対
パスを指定してください。

## プライバシー

詳細は[PRIVACY.md](PRIVACY.md)を参照してください。Usage値はメモリ上でのみ
保持します。アプリが起動するCodex App Serverは、利用者の既存アカウントと
OpenAIの規約に基づいてOpenAIと通信します。

## ライセンスと商標

ソースコードは[MIT License](LICENSE)で公開します。

本プロジェクトは非公式であり、OpenAIによる提供、承認、後援を受けていません。
Codex、ChatGPT、OpenAIおよび関連する名称はOpenAIの商標です。OpenAIのロゴや
OpenAI製ソフトウェアを本リポジトリへ同梱していません。
Codex本体はOpenAIから別途[Apache-2.0 License](https://github.com/openai/codex)
で公開されています。
