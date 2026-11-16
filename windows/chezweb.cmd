@echo off
setlocal DisableDelayedExpansion
"%~dp0..\bin\bash.exe" --noprofile --norc /app/start.sh --keep-directory %*
