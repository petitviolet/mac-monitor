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
3. 同じtickで、アプリごとの本体と子孫の合算(`ProcessTree.aggregates`)を計算します。検索欄に文字があるときだけ、全プロセスの起動時のPWD(`LaunchPWDCache.refresh`)も読みます。
4. `SamplingPipeline`がメインキューへ`Update`を渡し、`AppModel.apply`が`@Observable`の状態を更新します。`Update`のnilの項目は、その回に変化がないことを表します。`launchPWDs`は検索中で、前回から変わったときだけ入ります。
5. `ContentView`のタブと`MenuBarContent`が同じ`AppModel`を読みます。`AppModel`は`MacMonitorApp`のstaticプロパティに1つだけ置きます。Appの構造体は複数回作られることがあり、モデルが増えるとサンプリングも増えるからです。

選択を変えたときの詳細の読み込み(`SamplingPipeline.select`)も同じキューで実行し、古い結果は`ProcessDetailState.applying`で捨てます。検索を始めたときのPWDの読み込み(`SamplingPipeline.setSearchActive`)も同じキューです。

## 変えるときに知っておくこと

- **プロセス一覧の取得元は`/bin/ps`です。** 権限のないアプリの`proc_pid_rusage`は、rootなど他のユーザーのプロセスで拒否されます(実測で1,315件中231件)。`/bin/ps`はsetuid rootなので全件読めます。詳細は`libproc`と`sysctl`で読み、読めない項目はnilにして「権限なし」と表示します。
- **`ps`の環境変数は`LC_CTYPE=UTF-8`と`LC_NUMERIC=C`です。** `LC_ALL=C`にすると非ASCIIの名前が化けます。
- **killは`ProcessKiller`だけを通します。** `prepare`が確認ダイアログを開く時点の起動時刻と名前を控え、`send`が送信の直前に起動時刻を比べてPIDの再利用を検出します。`pid <= 1`と自分自身は拒否します。名前の比較には`ps`を使います。`ps -c`の名前はargv[0]由来で、1割強のプロセスで`proc_name`の値と異なります。`proc_name`と比べると、正常なプロセスを拒否してしまいます。
- **環境変数から読むのは`PWD`と`INIT_CWD`だけです。** `ProcArgsParser`はKERN_PROCARGS2の環境変数部分を名前の先頭のバイトで照合し、ほかの値は文字列にしません。トークンなどの秘密を画面に出さず、文字列として保持しないためです。検索のために全プロセスを読むとき(`ProcArgsParser.parseLaunchEnvironment`)は、argvも位置を数えるだけで文字列にしません。読む変数を増やすときは、この方針を見直してください。
- **起動時のPWDは`LaunchPWDCache`にPIDと起動時刻をキーにして覚えます。** 新しく現れたプロセスと、同じPIDで起動時刻が変わったものだけを読みます。状態を持つので、サンプリングのキューの上でだけ触ります。起動時刻の一覧(`ProcessStartTimeReader.readAll`)を読めなかった回は、キャッシュを変えずに前回の結果を使います。
- **端末判定(`TerminalLaunch`)はTTYと祖先のシェル名で行います。** `sh`はyarnやlaunchdのスクリプトも使うので数えません。端末を閉じて親を失ったプロセスはTTYも親のシェルもなくなるので、判定できません。
- **タブバーはツールバーのボタンで自作しています。** `TabView`の`tabItem`には画像が出ず、セグメントの`Picker`では文字が消えます。
- **表の並べ替えは見出しで切り替えます。** `Table`の`sortOrder`には`HeaderSort`を渡し、押された見出しを知るためだけに使います。並べ替えそのものと、押したときの規則はCoreの`ProcessSortKey.afterHeaderClick`、`AppSortOrder.afterHeaderClick`、`ProcessRanking`、`AppRanking`にあります。プロセスの表はCPUとメモリの多い順だけで、上位30件の選び方を兼ねます。
- **一覧と詳細ペインは`HStack`と`Divider`で並べます(`SplitLayout`)。** `HSplitView`はツールバーを含むウィンドウ全体の高さで作られ、区切り線がツールバーの上まで描かれます。
- **詳細ペインの幅は固定です(`DetailPaneLayout.width`)。** 最長のラベルとパスの幅を13ptのシステムフォントで実測して決めています。フォントや文言を変えたら測り直してください。ウィンドウの最小幅と既定の幅は、この幅と一覧の最小幅から計算します。
- **アプリアイコンは全面不透明の1024pxです。** 角丸で余白のあるicnsは、macOS 26で灰色のタイルの中に縮小して描画されます。
- **グリフは`Bundle.main`から読みます。** `scripts/build-app.sh`が`Contents/Resources/`へコピーするので、`swift run`ではSF Symbolsへフォールバックします。

## 検証するとき

- 既存のプロセスにシグナルを送らないでください。killを試すときは自分で起動したプロセスを使います。一覧の上位30件に出す必要があるなら、`perl -e 'alarm 60; while(1){}'`のようにCPUを使うものにします。
- `open build/MacMonitor.app`はユーザーのフォーカスを奪います。検証では`open -g`で起動してください。ユーザーが起動中のMacMonitorは終了させず、新しいビルドの反映は開き直しを依頼します。
- この環境の`screencapture`は`could not create image from display`で失敗します。実際のウィンドウの見た目を確認できなかったときは「未確認」と報告してください。

## 規約

- `Package.swift`はSwift言語モードをv5にしています。
- UI文言、コメント、READMEは日本語で書きます。
