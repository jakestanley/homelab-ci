# Recovery

## A scheduled (cron) pipeline never seems to run

Symptom: a repo has a `.woodpecker/*.yaml` file with `when: event: cron, cron:
"some-name"`, and it's supposed to run on a schedule (e.g. a periodic refresh/pull), but
it's never once fired, even though `push`/`manual` pipelines for the same repo work fine.

This means no Woodpecker Cron job named `"some-name"` is registered for that repo — the
YAML filter only matches against a Cron object created separately via the API/UI, it does
not create one. See the README's "Activate a repository" section for why. Check:

1. Repo settings → Cron tab in the Woodpecker UI. If it's empty, `add-repo.sh` was never
   run for this repo, or was run before the cron-registration step existed.
2. Re-run `./scripts/add-repo.sh owner/repo` — it's idempotent and safe against an
   already-active repo. It backfills the five standard cron jobs (15m/30m/1h/6h/24h) if
   missing, without touching anything else that's already correct.
3. To confirm the fix without waiting for the schedule, manually trigger the specific cron
   that matches your YAML's `cron:` name from the repo's Cron tab. Triggering one of the
   other four (unreferenced) names is expected to do nothing — that's normal, not a sign
   the fix failed.

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
