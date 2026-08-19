#!/usr/bin/env sh
# 构建浏览器版并就地放置 wasm,然后用任意静态服务器伺服本目录。
set -e
cd "$(dirname "$0")/.."
cargo build -p nes-wasm --target wasm32-unknown-unknown --release
cp target/wasm32-unknown-unknown/release/nes_wasm.wasm web/
echo "完成。本地试玩:python3 -m http.server -d web 8080  →  http://localhost:8080"
