# Dotfiles

- **.zshrc**: Zsh configuration with plugins and aliases.
- **claude-local**: runs Claude Code against a self-hosted Ollama server. Install with `install -m755 claude-local ~/.local/bin/`; override with `OLLAMA_URL`, `CLAUDE_LOCAL_MODEL`, `CLAUDE_LOCAL_CTX`.

## server/

Homelab Storage VM scripts, run by systemd timers.

- **update.sh**: pulls and restarts the Docker Compose stacks.
- **backup-config.sh**: encrypted restic backup of configs and databases to Google Drive.
- **notify-failure.sh**: Telegram alert for failed units, via `OnFailure=notify-failure@%n.service`.
