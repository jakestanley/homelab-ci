# Roadmap

- **Read-only token for agents to read pipeline logs.** Step containers are
  removed when a step finishes, but logs stay in Woodpecker's database and
  its API. Plan: a GitHub bot account with Read collaborator access, added
  as a Woodpecker user; its token saved to
  `~/.config/homelab/woodpecker-readonly.token`. Then write
  `scripts/pipeline-logs.sh` to fetch a pipeline's step logs with it.
  Waiting on Jake to create the bot account.
