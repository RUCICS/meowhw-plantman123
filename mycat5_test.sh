# 脚本在没有对mycat5.c进行修改的情况下，对mycat5.c进行性能分析
# 在终端中运行./mycat5_test.sh，分别测试A=( 8 16 32 64 128 256 512 1024 2048 4096 8192)
set -e
TEST_FILE="test.txt"
RESULT_DIR="test_result"
WARMUP_RUNS=2
BENCHMARK_RUNS=3
ORIGINAL_FILE="target/mycat5.c"
BACKUP_FILE="test/mycat5_backup.c"

echo "=== mycat5 Performance Analysis ==="


check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "ERROR: $1 command not found"
        exit 1
    fi
}

check_command "gcc"

# Check if bc is available for calculations
if ! command -v bc &> /dev/null; then
    USE_BC=false
else
    USE_BC=true
fi

# Create result and test directories
mkdir -p "$RESULT_DIR" "test"


cp "$ORIGINAL_FILE" "$BACKUP_FILE"

if [ ! -f "$TEST_FILE" ]; then
    echo "ERROR: Test file $TEST_FILE not found!"
    echo "Please make sure test.txt exists in the current directory."
    exit 1
else
    continue
fi


create_mycat5_variant() {
    local multiplier=$1
    local output_file="test/mycat5_A${multiplier}.c"
    
    # Copy original file
    cp "$BACKUP_FILE" "$output_file"
    
    # Replace the return statement in io_blocksize function
    if [[ "$multiplier" == *"."* ]]; then
        # Handle decimal multipliers
        # Convert 0.5 to division by 2, 1.5 to *3/2, etc.
        if [ "$multiplier" = "0.5" ]; then
            sed -i 's/return muti \* block_size;/return (muti * block_size) \/ 2;/' "$output_file"
        elif [ "$multiplier" = "1.5" ]; then
            sed -i 's/return muti \* block_size;/return (muti * block_size * 3) \/ 2;/' "$output_file"
        else
            # For other decimals, convert to integer math
            integer_mult=$(echo "$multiplier * 1000" | bc -l | cut -d. -f1)
            sed -i "s/return muti \* block_size;/return (muti * block_size * $integer_mult) \/ 1000;/" "$output_file"
        fi
    else
        # Handle integer multipliers
        sed -i "s/return muti \* block_size;/return muti * block_size * $multiplier;/" "$output_file"
    fi
    
    echo "$output_file"
}


compile_mycat5() {
    local source_file=$1
    local executable_file=$2
    
    gcc -O2 -o "$executable_file" "$source_file" -Wall 2>/dev/null
    return $?
}

benchmark_mycat5_simple() {
    local executable=$1
    local multiplier=$2
    
    if [ ! -f "$executable" ]; then
        echo "999.999"
        return 1
    fi
    
    # Use time command directly - more reliable
    local best_time="999.999"
    
    for i in {1..3}; do
        # First check if executable works
        if ! "$executable" "$TEST_FILE" > /dev/null 2>&1; then
            continue
        fi
        
        # Use time command to measure execution
        local time_output
        time_output=$({ time "$executable" "$TEST_FILE" > /dev/null; } 2>&1 | grep real | awk '{print $2}' | sed 's/[^0-9.]//g')
        
        # If time command failed, try alternative method
        if [[ ! $time_output =~ ^[0-9]+\.?[0-9]*$ ]]; then
            # Fallback to date method
            local start_time=$(date +%s.%N)
            if "$executable" "$TEST_FILE" > /dev/null 2>&1; then
                local end_time=$(date +%s.%N)
                if [ "$USE_BC" = true ]; then
                    time_output=$(echo "$end_time - $start_time" | bc -l 2>/dev/null)
                else
                    time_output=$(awk "BEGIN {printf \"%.6f\", $end_time - $start_time}" 2>/dev/null)
                fi
            fi
        fi
        
        # Validate and compare time
        if [[ $time_output =~ ^[0-9]+\.?[0-9]*$ ]]; then
            if [ "$USE_BC" = true ]; then
                if (( $(echo "$time_output > 0 && $time_output < $best_time" | bc -l 2>/dev/null || echo "0") )); then
                    best_time=$time_output
                fi
            else
                if awk "BEGIN {exit !($time_output > 0 && $time_output < $best_time)}"; then
                    best_time=$time_output
                fi
            fi
        fi
    done
    
    echo "$best_time"
}

# Test
A_VALUES=( 8 16 32 64 128 256 512 1024 2048 4096 8192)


declare -A results
best_A=1
best_time="1000"
echo "A    | Multiplier | Avg Time(s)"
echo "-----|------------|-----------"

for A in "${A_VALUES[@]}"; do
    # Create variant
    source_file=$(create_mycat5_variant "$A")
    executable_file="test/mycat5_A${A}"
    
    # Compile
    if compile_mycat5 "$source_file" "$executable_file"; then
        # Performance test
        time_result=$(benchmark_mycat5_simple "$executable_file" "$A")
        results["$A"]="$time_result"
        
        # Check if this is the best result using awk
        if awk "BEGIN {exit !($time_result < $best_time)}"; then
            best_time="$time_result"
            best_A="$A"
        fi
        
        printf "%-4s | %-10s | %s\n" "$A" "${A}x" "${time_result}"
    else
        echo "$A   | ${A}x        | COMPILE_FAILED"
        results["$A"]="FAILED"
    fi
done

echo "-----|------------|-----------"
echo "Best A value: $best_A"
echo "Best time: $best_time"
