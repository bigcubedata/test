#!/bin/sh
# 构建 tourney.nes:CHR 生成 → ca65 汇编 → ld65 链接
set -e
cd "$(dirname "$0")"
mkdir -p build
python3 tools/gen_chr.py build/chr.bin
ca65 src/tourney.s -g -o build/tourney.o
ld65 -C src/nrom.cfg build/tourney.o -o tourney.nes -m build/tourney.map -Ln build/tourney.lbl
echo "OK: tourney.nes ($(wc -c < tourney.nes) 字节)"
