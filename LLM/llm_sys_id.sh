#!/bin/bash

LOG_FILE="llm_system_check.log"
echo "Local LLM Optimization Diagnostic Report" > $LOG_FILE
echo "Generated: $(date)" >> $LOG_FILE
echo "========================================" >> $LOG_FILE

# Hardware Information
echo -e "\n[ HARDWARE INFORMATION ]" | tee -a $LOG_FILE

# CPU details
echo -e "\n# CPU DETAILS" | tee -a $LOG_FILE
lscpu | grep -E "Model name|Socket|Core|On-line|Thread|MHz|max" | tee -a $LOG_FILE
grep -m1 "flags" /proc/cpuinfo | grep -oE "\b(avx512f|avx2|avx|fma|sse4_2)\b" | sort -u | \
xargs -I {} echo "CPU FLAGS PRESENT: {}" | tee -a $LOG_FILE

# RAM information
echo -e "\n# MEMORY CONFIGURATION" | tee -a $LOG_FILE
free -h | awk '/Mem/{print "Total RAM: " $2 " | Available: " $7}' | tee -a $LOG_FILE
sudo dmidecode --type memory | grep -E "Type:|Speed:|Size:" | grep -v "Unknown" | \
uniq | head -6 | tee -a $LOG_FILE

# GPU detection
echo -e "\n# GPU CONFIGURATION" | tee -a $LOG_FILE
if command -v nvidia-smi &> /dev/null; then
    echo "NVIDIA GPU DETECTED" | tee -a $LOG_FILE
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv | tee -a $LOG_FILE
elif command -v rocm-smi &> /dev/null; then
    echo "AMD GPU DETECTED" | tee -a $LOG_FILE
    rocm-smi --showproductname | tee -a $LOG_FILE
else
    echo "No dedicated GPU detected - Using CPU mode" | tee -a $LOG_FILE
fi

# Disk performance
echo -e "\n# STORAGE PERFORMANCE" | tee -a $LOG_FILE
df -h --output=source,fstype,size,avail,pcent /home | tee -a $LOG_FILE
echo -e "\n# DISK SPEED (Sequential Read - 1GB Test)" | tee -a $LOG_FILE
if command -v fio &> /dev/null; then
    fio --name=temp_test --rw=read --bs=1M --size=1G --runtime=10s --output-format=json | \
    jq '.jobs[0].read.bw' | awk '{print "Throughput: " $1/1024 " MB/s"}' | tee -a $LOG_FILE
else
    echo "Install 'fio' for precise disk benchmarks" | tee -a $LOG_FILE
fi

# Software Environment
echo -e "\n[ SOFTWARE ENVIRONMENT ]" | tee -a $LOG_FILE

# Acceleration libraries
echo -e "\n# ACCELERATION LIBRARIES" | tee -a $LOG_FILE
ldconfig -p | grep -E "libcublas|librocm|libonednn|libopenblas" | awk -F'> ' '{print $2}' | \
sort | uniq | tee -a $LOG_FILE

# Python environment
echo -e "\n# PYTHON ENVIRONMENT" | tee -a $LOG_FILE
command -v python3 && python3 -c "import sys; print(f'Python {sys.version}')" | tee -a $LOG_FILE
python3 -m pip list 2>/dev/null | grep -E "torch|tensorflow|transformers|llama-cpp-python" | tee -a $LOG_FILE

# Container support
echo -e "\n# CONTAINER SUPPORT" | tee -a $LOG_FILE
if command -v docker &> /dev/null; then
    docker --version | tee -a $LOG_FILE
    docker info 2>/dev/null | grep "Runtimes" | tee -a $LOG_FILE
else
    echo "Docker not installed" | tee -a $LOG_FILE
fi

# Kernel and OS
echo -e "\n# SYSTEM VERSION" | tee -a $LOG_FILE
uname -r | awk '{print "Kernel: " $1}' | tee -a $LOG_FILE
cat /etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2 | tee -a $LOG_FILE

# Environment Variables
echo -e "\n# RELEVANT ENV VARIABLES" | tee -a $LOG_FILE
printenv | grep -E "CUDA_VISIBLE_DEVICES|HSA_OVERRIDE|OMP_NUM_THREADS|GGML_CUBLAS|LIBRARY_PATH" | tee -a $LOG_FILE

# Performance Recommendations
echo -e "\n[ PERFORMANCE RECOMMENDATIONS ]" >> $LOG_FILE
grep -q "avx512" $LOG_FILE && echo "- AVX512 detected: Use LLAMA/GGUF builds with AVX512 support" >> $LOG_FILE
grep -q "NVIDIA" $LOG_FILE && echo "- NVIDIA GPU present: Enable CUDA in model loaders" >> $LOG_FILE
grep -q "No dedicated GPU" $LOG_FILE && echo "- Consider CPU quantization (q4_0, q5_K_M)" >> $LOG_FILE
grep "Throughput" $LOG_FILE | awk -F: '{if ($2 < 500) print "- Slow storage: Use tmpfs for model weights"}' >> $LOG_FILE

echo -e "\nDiagnostic complete. Report saved to $LOG_FILE"
