#!/usr/bin/env bash
# Logging helpers for walter CLI

# Color codes (only if stdout is a TTY)
if [[ -t 1 ]]; then
  C_RESET='\033[0m'
  C_BOLD='\033[1m'
  C_DIM='\033[2m'
  C_RED='\033[31m'
  C_GREEN='\033[32m'
  C_YELLOW='\033[33m'
  C_BLUE='\033[34m'
  C_CYAN='\033[36m'
else
  C_RESET=''; C_BOLD=''; C_DIM=''
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''
fi

log_info()  { printf "${C_CYAN}→${C_RESET} %s\n" "$*"; }
log_ok()    { printf "${C_GREEN}✓${C_RESET} %s\n" "$*"; }
log_warn()  { printf "${C_YELLOW}⚠${C_RESET} %s\n" "$*" >&2; }
log_err()   { printf "${C_RED}✗${C_RESET} %s\n" "$*" >&2; }
log_step()  { printf "\n${C_BOLD}${C_BLUE}== %s ==${C_RESET}\n" "$*"; }
log_dim()   { printf "${C_DIM}%s${C_RESET}\n" "$*"; }
