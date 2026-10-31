#!/usr/bin/env bash
# Kill running Wolfram LSP server process to release Wolfram license

pids=$(pgrep -f "Wolfram.*LSP")

if [ -n "$pids" ]; then
    echo "Found Wolfram LSP process(es): $pids"
    echo "$pids" | xargs kill -9
    echo "Killed Wolfram LSP process(es)."
else
    echo "No Wolfram LSP processes found."
fi
