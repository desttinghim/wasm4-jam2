#!/usr/bin/env bash

zig build opt -Drelease-small
mkdir -p bundle/html
mkdir -p bundle/linux
mkdir -p bundle/windows
mkdir -p bundle/mac
mkdir -p bundle/cart
npx wasm4 bundle --html bundle/html/index.html --linux bundle/linux/punch-em-up --windows bundle/windows/punch-em-up.exe --mac bundle/mac/punch-em-up zig-out/lib/opt.wasm
cp zig-out/lib/opt.wasm bundle/cart/punch-em-up.wasm
