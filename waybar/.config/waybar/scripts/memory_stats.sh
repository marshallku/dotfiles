#!/bin/bash

mem_used=$(free -h | grep Mem | awk '{print $3}')
mem_total=$(free -h | grep Mem | awk '{print $2}')

echo "{\"text\": \"   $mem_used / $mem_total\", \"tooltip\": \"Memory: ${mem_used} / ${mem_total}\"}"

