# homelab-ci

Woodpecker CI runs here as a long-running Docker Compose service.

Assumptions:
- Service identity is `ci`, matching `services.ci` in the sibling registry.
- The external service URL is `https://ci.stanley.arpa`.
- The upstream port is fixed from the registry entry and mapped as `20034:8000`.
- Reverse proxy, DNS, and any external infrastructure wiring remain owned by `homelab-infra`.

## Files

- `docker-compose.yml`: Woodpecker server and agent.
- `.env.example`: Required runtime configuration placeholders.
- `scripts/add-repo.sh`: Activates a repository through the Woodpecker API.
- `scripts/up.sh`: Idempotent entrypoint for `docker compose up -d`.
- `RECOVERY.md`: Basic recovery operations.

## Required configuration

Create `.env` from `.env.example` and set:
- `WOODPECKER_ADMIN`: GitHub username to grant admin access.
- `WOODPECKER_HOST`: External URL used by Woodpecker. Default is `https://ci.stanley.arpa`.
- `WOODPECKER_OPEN`: Leave this `false` normally. Temporarily set it to `true` only for first-login/bootstrap if closed registration blocks your admin login, then set it back to `false` and recreate `woodpecker-server`.
- `WOODPECKER_POLL_INTERVAL`: How often Woodpecker polls GitHub for changes when webhooks cannot reach this instance. `5m` is the default in this repo.
- `WOODPECKER_TOKEN`: Woodpecker personal access token for local helper scripts such as `scripts/add-repo.sh`.
- `GITHUB_CLIENT_ID`: GitHub OAuth client id.
- `GITHUB_CLIENT_SECRET`: GitHub OAuth client secret.
- `AGENT_SECRET`: Shared secret used by the Woodpecker server and agent.

## Start

```bash
./scripts/up.sh
```

## Activate a repository

Create a Woodpecker personal access token in your Woodpecker profile, add it to `.env` as
`WOODPECKER_TOKEN`, then activate a repo without using the UI:

```bash
./scripts/add-repo.sh owner/repo
```

The helper also enables trusted volume access for the repository so pipeline mounts work.
That trust change requires a Woodpecker server admin token; if the token can activate repos
but cannot update trust, the script exits with an error after activation.
It also ensures five cron jobs exist on the default branch: every 15 minutes, every 30
minutes, every hour, every 6 hours, and every 24 hours.

You'll probably want the following repos as a minimum:
- homelab-infra
- nix

## Notes

- The agent uses the Docker backend and mounts the host Docker socket.
- Every pipeline step receives the host CA certificate from `/etc/homelab/certs/ca/ca.crt` at `/etc/ssl/certs/homelab-ca.crt`.
- Pipelines that `curl` homelab services using that CA should use `curl --cacert /etc/ssl/certs/homelab-ca.crt https://...` or set `CURL_CA_BUNDLE=/etc/ssl/certs/homelab-ca.crt`.
- The agent stores its config in the named volume `woodpecker-agent-config`.
