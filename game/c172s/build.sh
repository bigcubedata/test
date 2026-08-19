#!/bin/sh
# 构建 c172s.nes:CHR 生成 → ca65 汇编 → ld65 链接
set -e
cd "$(dirname "$0")"
mkdir -p build
python3 tools/gen_chr.py build/chr.bin
ca65 src/c172s.s -g -o build/c172s.o
ld65 -C src/nrom.cfg build/c172s.o -o c172s.nes -m build/c172s.map
echo "OK: c172s.nes ($(wc -c < c172s.nes) 字节)"
