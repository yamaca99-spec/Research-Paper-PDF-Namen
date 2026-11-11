#!/usr/bin/env bash
# End-to-End-Test (macOS): benennt echte und künstliche Paper-PDFs mit der gebauten App um
# und prüft die erwarteten Dateinamen. Aufruf nach ./scripts/build-app.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/Paper Renamer.app/Contents/MacOS/PaperRenamer"
WORK="$(mktemp -d)"
FAILED=0

cp "$ROOT"/Tests/Fixtures/*.pdf "$WORK/"

download() {
  if curl -fsSL --max-time 90 -A "Mozilla/5.0 (Macintosh)" -o "$WORK/$1" "$2"; then
    return 0
  fi
  echo "WARNUNG: Download fehlgeschlagen: $2"
  rm -f "$WORK/$1"
  return 1
}

HAVE_ARXIV=0
HAVE_PLOS=0
download "1706.03762v7.pdf" "https://arxiv.org/pdf/1706.03762v7" && HAVE_ARXIV=1
download "journal.pmed.0020124.pdf" \
  "https://journals.plos.org/plosmedicine/article/file?id=10.1371/journal.pmed.0020124&type=printable" && HAVE_PLOS=1

echo "==> Vorher:"
ls -1 "$WORK"
echo

"$BIN" --cli --debug --rename "$WORK"/*.pdf

echo
echo "==> Nachher:"
ls -1 "$WORK"
echo

expect() {
  if [[ -f "$WORK/$1" ]]; then
    echo "OK    $1"
  else
    echo "FEHLT $1"
    FAILED=1
  fi
}

expect "LeCun et al. (2015) Deep learning.pdf"
expect "Silver et al. (2016) Mastering the game of Go with deep neural networks and tree search.pdf"
expect "Mustermann & Beispiel (2023) A completely fictional study on automatically renaming scientific PDF files.pdf"
[[ $HAVE_ARXIV -eq 1 ]] && expect "Vaswani et al. (2017) Attention Is All You Need.pdf"
[[ $HAVE_PLOS -eq 1 ]] && expect "Ioannidis (2005) Why Most Published Research Findings Are False.pdf"

rm -rf "$WORK"
exit $FAILED
