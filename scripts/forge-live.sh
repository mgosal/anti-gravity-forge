#!/bin/bash
# A zero-dependency live pipeline TUI dashboard

WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)/forge_workspaces"
mkdir -p "$WORKSPACE_DIR"

while true; do
  clear
  echo "================================================================================"
  echo "                       IRON TECH FORGE LIVE DASHBOARD                           "
  echo "================================================================================"
  echo "Time: $(date)"
  echo "Watching: ${WORKSPACE_DIR}"
  echo "Press Ctrl+C to exit"
  echo "--------------------------------------------------------------------------------"
  
  RECENT_LOGS=$(find "$WORKSPACE_DIR" -type f \( -name "pipeline.log" -o -name "tool-dispatch.log" \) -mmin -60 2>/dev/null | sort || true)
  
  if [ -z "$RECENT_LOGS" ]; then
    echo ""
    echo "No agent activity logged in the last 60 minutes."
    echo "Waiting for the polling daemon to pick up an issue..."
  else
    for log in $RECENT_LOGS; do
      # Extract repo name and issue number from path for aesthetics
      # Path format: .../forge_workspaces/mgosal-iron-tech-forge/issue-23/.forge-meta/pipeline.log
      REL_PATH="${log#$WORKSPACE_DIR/}"
      SLUG=$(echo "$REL_PATH" | cut -d'/' -f1)
      ISSUE=$(echo "$REL_PATH" | cut -d'/' -f2)
      LOG_NAME=$(echo "$REL_PATH" | awk -F'/' '{print $NF}')
      
      echo -e "\033[1;36m▶ [${SLUG} / ${ISSUE}] ${LOG_NAME}\033[0m"
      tail -n 12 "$log"
      echo "--------------------------------------------------------------------------------"
    done
  fi
  
  sleep 2
done
