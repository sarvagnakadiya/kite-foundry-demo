#!/bin/zsh

set -euo pipefail

# Usage: ./kiteup.sh <ContractName>
# Example: ./kiteup.sh SimpleStaking

if [ $# -lt 1 ]; then
  echo "Usage: $0 <ContractName>" >&2
  exit 1
fi

CONTRACT_NAME="$1"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$ROOT_DIR/out"
SRC_DIR="$ROOT_DIR/src"
FLATTEN_DIR="$ROOT_DIR/flattened"

# Base URL (override with KITE_BASE_URL env var)
BASE_URL="https://kite-app-omega.vercel.app"
UPLOAD_URL="$BASE_URL/api/upload"

# 1. Build all contracts (force rebuild to ensure artifact exists)
echo "[INFO] Building contracts..."
forge build --force >/dev/null

# 2. Find artifact JSON for the contract
echo "[INFO] Searching artifact for $CONTRACT_NAME..."
artifact_path=$(find "$OUT_DIR" -type f -name "$CONTRACT_NAME.json" | head -n1 || true)

if [ -z "$artifact_path" ]; then
  echo "[ERROR] Artifact not found for $CONTRACT_NAME after build" >&2
  exit 2
fi

echo "[INFO] Artifact path: $artifact_path"

if ! command -v jq >/dev/null 2>&1; then
  echo "[ERROR] jq is required but not installed." >&2
  exit 3
fi

# 3. Extract fields from artifact
abi=$(jq -c '.abi' "$artifact_path")
bytecode=$(jq -r '.bytecode.object // .bytecode // ""' "$artifact_path")
compiler=$(jq -r '.metadata.compiler.version // .rawMetadata.compiler.version // ""' "$artifact_path")
optimizer_enabled=$(jq -r '(.metadata.settings.optimizer.enabled // .rawMetadata.settings.optimizer.enabled // false)' "$artifact_path")
optimizer_runs=$(jq -r '(.metadata.settings.optimizer.runs // .rawMetadata.settings.optimizer.runs // 200)' "$artifact_path")
evm_version=$(jq -r '(.metadata.settings.evmVersion // .rawMetadata.settings.evmVersion // "")' "$artifact_path")
remappings=$(jq -c '(.metadata.settings.remappings // .rawMetadata.settings.remappings // [])' "$artifact_path")

# Normalize optimizer JSON
if [ "$optimizer_enabled" = "true" ] || [ "$optimizer_enabled" = "false" ]; then
  optimizer_json=$(jq -n --argjson en "$optimizer_enabled" --argjson rn "$optimizer_runs" '{enabled: $en, runs: $rn}')
else
  optimizer_json=$(jq -n --argjson en false --argjson rn 200 '{enabled: $en, runs: $rn}')
fi

# 4. Flatten contract
mkdir -p "$FLATTEN_DIR"

# Try to find source in src/ folder
source_file=$(grep -RIl --include='*.sol' --exclude-dir={node_modules,lib,out} "contract $CONTRACT_NAME\b" "$SRC_DIR" | head -n1 || true)

if [ -z "$source_file" ]; then
  echo "[ERROR] Could not find source file for contract $CONTRACT_NAME in src/" >&2
  exit 4
fi

FLATTENED_PATH="$FLATTEN_DIR/${CONTRACT_NAME}_flat.sol"

echo "[INFO] Flattening $CONTRACT_NAME..."
forge flatten "$source_file" -o "$FLATTENED_PATH" >/dev/null

flattened_source=$(<"$FLATTENED_PATH")

# 5. Build final JSON
echo "[INFO] Building final JSON..." >&2

response=$(
  jq -n \
    --arg name "$CONTRACT_NAME" \
    --arg path "$artifact_path" \
    --arg bytecode "$bytecode" \
    --arg compiler "$compiler" \
    --arg sourcePath "$FLATTENED_PATH" \
    --arg source "$flattened_source" \
    --arg evmVersion "$evm_version" \
    --argjson remappings "$remappings" \
    --argjson optimizer "$optimizer_json" \
    --argjson abi "$abi" \
    '{
      name: $name,
      artifactPath: $path,
      compilerVersion: $compiler,
      abi: $abi,
      bytecode: $bytecode,
      flattenedSourcePath: $sourcePath,
      flattenedSource: $source,
      settings: {
        evmVersion: $evmVersion,
        remappings: $remappings,
        optimizer: $optimizer
      }
    }' | curl -sS -X POST -H "Content-Type: application/json" --data-binary @- "$UPLOAD_URL"
)

inserted_id=$(echo "$response" | jq -r '.insertedId // empty')

if [ -z "$inserted_id" ]; then
  echo "[ERROR] Upload failed or no insertedId in response" >&2
  echo "$response" >&2
  exit 5
fi

echo "$inserted_id"
