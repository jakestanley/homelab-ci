# Recovery

## Check status

```bash
docker compose ps
```

## View logs

```bash
docker compose logs --tail=200 woodpecker-server woodpecker-agent
```

## Restart services

```bash
docker compose up -d
```

## Recreate containers after config changes

```bash
docker compose up -d --force-recreate
```

## Stop services

```bash
docker compose down
```

## Reset only service state

Woodpecker server state is stored in the named Docker volume `woodpecker-server-data`.
Do not remove it unless you intend to discard server state and re-bootstrap the service.

## Native apply agent (host systemd service, not Docker Compose)

This is a separate process from everything above — it's not managed by
`docker compose` at all. See the README's "Native apply agent" section
for what it is and why it exists.

Check status / logs:

```bash
sudo systemctl status woodpecker-agent --no-pager
sudo journalctl -u woodpecker-agent -n 200 --no-pager
```

Restart:

```bash
sudo systemctl restart woodpecker-agent
```

Reinstall from scratch (safe to re-run; idempotent):

```bash
sudo bash scripts/install-native-apply-agent.sh /path/to/woodpecker-agent.deb
```

If the Woodpecker server is ever rebuilt/re-bootstrapped (its
`AGENT_SECRET` changes), update `/etc/woodpecker/woodpecker-agent.env`
on the host to match the new value in `.env` and restart the service —
re-running the install script does this for you.

Config lives outside this repo, on the host:
- `/etc/woodpecker/woodpecker-agent.env` — agent config, `600 root:root`
- `/etc/sudoers.d/woodpecker-apply` — the scoped privilege grant
- `/var/lib/woodpecker-apply/` — per-run workflow checkouts (the `local`
  backend's working directory; safe to clear, it's fully regenerated
  from the `homelab-infra` repo on every run)
- `/var/lib/woodpecker/agent.conf` — the agent's server-assigned identity
  (owned by `woodpecker`, via the systemd unit's `StateDirectory=`).
  Deleting it just means the agent re-registers as a new agent entry on
  next start — safe, just leaves a stale row in Woodpecker's agent list
  you may want to remove from the UI.
