#!/bin/bash
# Runs right after llama-server starts (ExecStartPost): time from start to first /health 200.
start=$(date +%s.%N)                                  # stopwatch start
for _ in $(seq 300); do                               # at most 300 × 0.2 s = 60 s
  curl -sf http://127.0.0.1:8081/health > /dev/null && break   # 200 → model loaded → leave the loop
  sleep 0.2
done
curl -sf http://127.0.0.1:8081/health > /dev/null || exit 0     # never got 200 → write nothing, don't fail
end=$(date +%s.%N)                                    # stopwatch stop
seconds=$(awk "BEGIN {print $end - $start}")          # decimal subtraction
dir=/var/lib/prometheus/node-exporter                 # node_exporter's textfile folder
echo "# TYPE llama_model_load_seconds gauge" >  $dir/llama.prom.tmp
echo "llama_model_load_seconds $seconds"     >> $dir/llama.prom.tmp
mv $dir/llama.prom.tmp $dir/llama.prom                # instant swap, never half a file
