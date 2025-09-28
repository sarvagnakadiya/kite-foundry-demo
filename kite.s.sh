#!/bin/bash
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <ContractName|ScriptFile>"
    exit 1
fi

INPUT="$1"
SCRIPT_DIR="./script"
OUTPUT="$(mktemp)"
trap 'rm -f "$OUTPUT"' EXIT

# Base URL (override with KITE_BASE_URL env var)
BASE_URL="${KITE_BASE_URL:-https://kite-app-omega.vercel.app}"
UPLOAD_URL="$BASE_URL/api/upload"

# Determine the file
if [[ "$INPUT" == *.sol ]]; then
    FILE="$SCRIPT_DIR/$INPUT"
else
    FILE="$SCRIPT_DIR/$INPUT.s.sol"
fi

if [ ! -f "$FILE" ]; then
    echo "Error: File $FILE not found"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "[ERROR] jq is required but not installed." >&2
    exit 3
fi

echo '{ "functions": [' > "$OUTPUT"
first=true

# Load constants
CONST_NAMES=()
CONST_VALUES=()
while read -r line; do
    echo "$line" | grep -q 'constant' || continue
    # address constant
    echo "$line" | grep -q 'address constant' && {
        name=$(echo "$line" | awk '{print $3}')
        value=$(echo "$line" | awk '{print $5}' | tr -d ';')
        CONST_NAMES+=("$name")
        CONST_VALUES+=("$value")
    }
    # uint256 constant
    echo "$line" | grep -q 'uint256 constant' && {
        name=$(echo "$line" | awk '{print $3}')
        value=$(echo "$line" | awk '{print $5}' | tr -d ';')
        CONST_NAMES+=("$name")
        CONST_VALUES+=("$value")
    }
done < "$FILE"

get_constant() {
    key="$1"
    # sanitize key to ensure it matches parsed constant names
    key=$(echo "$key" | tr -d ');')
    for i in "${!CONST_NAMES[@]}"; do
        if [ "${CONST_NAMES[$i]}" = "$key" ]; then
            echo "${CONST_VALUES[$i]}"
            return
        fi
    done
    echo "$key"
}

# Extract run() function lines
sed -n '/function run/,/}/p' "$FILE" | grep -v 'function run' | grep -v '^}' | while read -r line; do
    # Remove spaces
    line=$(echo "$line" | tr -d ' ')

    # Match IERC20 approve
    if echo "$line" | grep -q 'IERC20('; then
        if echo "$line" | grep -q '\.approve('; then
            # Extract inside parentheses
            inside=$(echo "$line" | sed 's/.*IERC20(\(.*\))\.approve(\(.*\))/\1,\2/')
            contract_addr=$(echo "$inside" | cut -d',' -f1)
            spender=$(echo "$inside" | cut -d',' -f2)
            amount=$(echo "$inside" | cut -d',' -f3)

            # Map constants: IERC20(CONTRACT).approve(SPENDER, AMOUNT)
            contract_addr=$(get_constant "$contract_addr")
            spender=$(get_constant "$spender")
            amount=$(get_constant "$amount")

            [ "$first" = false ] && echo ',' >> "$OUTPUT"
            first=false

            cat >> "$OUTPUT" <<EOF
{
  "name": "approve",
  "signature": "approve(address spender, uint256 amount)",
  "contract": "IERC20",
  "contract_address": "$contract_addr",
  "params": [
    {"name": "spender", "type": "address", "value": "$spender"},
    {"name": "amount", "type": "uint256", "value": "$amount"}
  ]
}
EOF
        fi
    fi

    # Match ISimpleStaking stake/withdraw
    if echo "$line" | grep -q 'ISimpleStaking('; then
        fn=$(echo "$line" | sed 's/.*ISimpleStaking([^)]*)\.\([a-z]*\)(\(.*\))/\1/')
        # sanitize: remove any trailing semicolons accidentally captured in fn
        fn=$(echo "$fn" | tr -d ';')
        param=$(echo "$line" | sed 's/.*ISimpleStaking([^)]*)\.[a-z]*(\(.*\))/\1/' | tr -d ')')
        # sanitize: remove stray semicolons from captured param
        param=$(echo "$param" | tr -d ';')
        contract_addr=$(echo "$line" | sed 's/.*ISimpleStaking(\([^)]*\)).*/\1/')

        contract_addr=$(get_constant "$contract_addr")
        param=$(get_constant "$param")

        [ "$first" = false ] && echo ',' >> "$OUTPUT"
        first=false

        cat >> "$OUTPUT" <<EOF
{
  "name": "$fn",
  "signature": "$fn(uint256 amount)",
  "contract": "ISimpleStaking",
  "contract_address": "$contract_addr",
  "params": [
    {"name": "amount", "type": "uint256", "value": "$param"}
  ]
}
EOF
    fi
done

echo ']}' >> "$OUTPUT"

response=$(curl -sS -X POST -H "Content-Type: application/json" --data-binary @"$OUTPUT" "$UPLOAD_URL")
inserted_id=$(echo "$response" | jq -r '.insertedId // empty')

if [ -z "$inserted_id" ]; then
    echo "[ERROR] Upload failed or no insertedId in response" >&2
    echo "$response" >&2
    exit 5
fi

echo "https://kite-app-omega.vercel.app/tx/$inserted_id"
