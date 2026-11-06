# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

MacMonitorは、アクティビティモニタのようなmacOSアプリです。SwiftPMとSwiftUIで作り、外部ライブラリは使いません。プロセスへのシグナル送信と他プロセスの情報取得があるので、App Sandboxは無効です。機能の制約はREADME.mdの「既知の制約」に書いてあります。

## コマンド

```bash
make test-ai    # AI用。失敗行と最終行だけを出す。警告もエラーにする
make test       # 人用。全出力を出す
make app        # build/MacMonitor.appを生成する。ad-hoc署名とLaunchServicesへの登録も行う
make icons      # assets-src/icons/の原画からResources/のアイコンを作り直す。uvが必要
open build/MacMonitor.app

scripts/test-ai.sh --filter PSRunnerTests    # 1つのテストクラスだけを実行する
scripts/test-ai.sh --filter PSRunnerTests/testName
```

`make test-ai`には引数を渡せないので、テストを絞るときは`scripts/test-ai.sh`を直接呼びます。

開発者のシェルでは`make`が`sed`へパイプする関数になっていて、`$?`が常に0になります。終了コードを見るときは`command make`を使ってください。

## 構成

- `Sources/MacMonitorCore`: 値の取得、パース、合算、killの判定を持ちます。FoundationとDarwinだけに依存し、テストはこのターゲットに対して書きます。
- `Sources/MacMonitor`: SwiftUIの画面とAppKitに依存する処理を持ちます。テストターゲットがないので、テストしたい判定はCoreの純粋関数へ出します(例: `ProcessDetailState`)。

データは次の順に流れます。

1. `SerialTicker`が専用のキューで5秒ごとに(`SamplingPipeline.interval`)`SamplingPipeline.tick()`を呼びます。前回の処理が終わるまで次は始まりません。
2. `SystemSampler`が`/bin/ps`、CPU、メモリ、ディスク、ネットワークを読み、`SystemSnapshot`にまとめます。
3. `SamplingPipeline`がメインキューへ`Update`を渡し、`AppModel.apply`が`@Observable`の状態を更新します。
4. `ContentView`のタブと`MenuBarContent`が同じ`AppModel`を読みます。`AppModel`は`MacMonitorApp`のstaticプロパティに1つだけ置きます。Appの構造体は複数回作られることがあり、モデルが増えるとサンプリングも増えるからです。

選択を変えたときの詳細の読み込みも同じキューで実行します(`SamplingPipeline.select`)。古い結果は`ProcessDetailState.applying`で捨てます。

## 変えるときに知っておくこと

- **プロセス一覧の取得元は`/bin/ps`です。** 権限のないアプリの`proc_pid_rusage`は、rootなど他のユーザーのプロセスで拒否されます(実測で1,315件中231件)。`/bin/ps`はsetuid rootなので全件読めます。詳細は`libproc`と`sysctl`で読み、読めない項目はnilにして「権限なし」と表示します。
- **`ps`の環境変数は`LC_CTYPE=UTF-8`と`LC_NUMERIC=C`です。** `LC_ALL=C`にすると非ASCIIの名前が化けます。
- **killは`ProcessKiller`だけを通します。** `prepare`が確認ダイアログを開く時点の起動時刻と名前を控え、`send`が送信の直前に起動時刻を比べてPIDの再利用を検出します。`pid <= 1`と自分自身は拒否します。名前の比較には`ps`を使います。`ps -c`の名前はargv[0]由来で、1割強のプロセスで`proc_name`の値と異なります。`proc_name`と比べると、正常なプロセスを拒否してしまいます。
- **環境変数から読むのは`PWD`と`INIT_CWD`だけです。** `ProcArgsParser`はKERN_PROCARGS2の環境変数部分を名前の先頭のバイトで照合し、ほかの値は文字列にしません。トークンなどの秘密を画面に出さず、文字列として保持しないためです。読む変数を増やすときは、この方針を見直してください。
- **端末判定(`TerminalLaunch`)はTTYと祖先のシェル名で行います。** `sh`はyarnやlaunchdのスクリプトも使うので数えません。端末を閉じて親を失ったプロセスはTTYも親のシェルもなくなるので、判定できません。
- **タブバーはツールバーのボタンで自作しています。** `TabView`の`tabItem`には画像が出ず、セグメントの`Picker`では文字が消えます。
- **アプリアイコンは全面不透明の1024pxです。** 角丸で余白のあるicnsは、macOS 26で灰色のタイルの中に縮小して描画されます。
- **グリフは`Bundle.main`から読みます。** `scripts/build-app.sh`が`Contents/Resources/`へコピーするので、`swift run`ではSF Symbolsへフォールバックします。

## 検証するとき

- 既存のプロセスにシグナルを送らないでください。killを試すときは自分で起動したプロセスを使います。一覧の上位30件に出す必要があるなら、`perl -e 'alarm 60; while(1){}'`のようにCPUを使うものにします。
- `open build/MacMonitor.app`はユーザーのフォーカスを奪います。検証では`open -g`で起動してください。ユーザーが起動中のMacMonitorは終了させず、新しいビルドの反映は開き直しを依頼します。
- この環境の`screencapture`は`could not create image from display`で失敗します。実際のウィンドウの見た目を確認できなかったときは「未確認」と報告してください。

## 規約

- `Package.swift`はSwift言語モードをv5にしています。
- UI文言、コメント、READMEは日本語で書きます。
