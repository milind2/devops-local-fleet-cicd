#!/bin/bash
# Build llama-server from source for one llama.cpp version; cached per version.
set -euo pipefail
version="${1:?usage: build-llama.sh <llama.cpp tag, e.g. b11154>}"
cache="$HOME/.cache/llama/$version"
src="$HOME/.cache/llama/src/$version"

if [ -x "$cache/llama-server" ]; then
  echo "cache hit: $cache/llama-server"
  exit 0
fi

echo "cache miss: building llama.cpp $version"
rm -rf "$src"
git clone --depth 1 --branch "$version" https://github.com/ggml-org/llama.cpp "$src"
cmake -S "$src" -B "$src/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DLLAMA_CURL=OFF -DGGML_NATIVE=OFF
cmake --build "$src/build" --target llama-server -j "$(nproc)"
mkdir -p "$cache"
cp "$src/build/bin/llama-server" "$cache/.llama-server.tmp"
mv "$cache/.llama-server.tmp" "$cache/llama-server"
echo "built and cached: $cache/llama-server"
