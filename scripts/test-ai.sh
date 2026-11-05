#!/usr/bin/env bash
set -uo pipefail

# AI用のテスト入口。ランナーはmake testと同じswift testで、出力だけを絞る。
#
# 残す行はXCTestの失敗行(file.swift:行: error:)とコンパイルエラー(file.swift:行:桁: error:)に絞る。
# どちらも「.swift:行」で始まる位置情報を持ち、形の似た進捗やバックトレースと混ざらない。
# 警告はビルド側でエラーにする。別のscratch-pathを使うので、make testとの差分ビルドに結果が左右されず、
# 警告のあるファイルはビルドが成功しないため、次回も必ずコンパイルされる。
# 引数はswift testへそのまま渡す。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$ROOT/.build/ai"
# 同時に実行してもログが混ざらないように、実行ごとに別のファイルへ書く。
LOG="$(mktemp "${TMPDIR:-/tmp}/mac-monitor-test-ai.XXXXXX")"

cd "$ROOT" || exit 1
swift test --scratch-path "$SCRATCH" -Xswiftc -warnings-as-errors "$@" >"$LOG" 2>&1
status=$?

# ログにNULなどが混ざると、grepは-aなしでは一致した行の代わりに「Binary file ... matches」を返す。
# LC_ALL=Cは、UTF-8として不正なバイトで行が読めなくなるのを防ぐ。
problems="$(LC_ALL=C grep -aE '\.swift:[0-9]+(:[0-9]+)?: error: ' "$LOG" | LC_ALL=C sort -u)"
summary="$(LC_ALL=C grep -aE '^[[:space:]]*Executed [0-9]+ tests?,' "$LOG" | tail -1)"
count="$(printf '%s\n' "$summary" | LC_ALL=C sed -E 's/^[[:space:]]*Executed ([0-9]+) .*/\1/')"

fail_with_raw_log() {
  echo "test-ai: $1"
  echo "--- 生ログ: $LOG"
  cat "$LOG"
  exit 1
}

if [ -z "$summary" ]; then
  fail_with_raw_log "テストの最終行が見つかりません(exit $status)"
fi
case "$count" in
  '' | *[!0-9]*) fail_with_raw_log "テストの最終行から件数を読めません: $summary" ;;
esac
if [ "$count" = "0" ]; then
  fail_with_raw_log "実行されたテストが0件です(exit $status)"
fi
if [ "$status" -ne 0 ]; then
  [ -z "$problems" ] && fail_with_raw_log "swift testが失敗しましたが、印のある行がありません(exit $status)"
  printf '%s\n' "$problems"
  printf '%s\n' "$summary"
  exit "$status"
fi

printf '%s\n' "$summary"
