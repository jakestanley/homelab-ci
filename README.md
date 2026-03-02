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
- `scripts/up.sh`: Idempotent entrypoint for `docker compose up -d`.
- `RECOVERY.md`: Basic recovery operations.

## Required configuration

Create `.env` from `.env.example` and set:
- `WOODPECKER_ADMIN`: GitHub username to grant admin access.
- `WOODPECKER_HOST`: External URL used by Woodpecker. Default is `http://ci.stanley.arpa`.
- `GITHUB_CLIENT_ID`: GitHub OAuth client id.
- `GITHUB_CLIENT_SECRET`: GitHub OAuth client secret.
- `AGENT_SECRET`: Shared secret used by the Woodpecker server and agent.

## Start

```bash
./scripts/up.sh
```

## Notes

- The agent uses the local backend and mounts `/var/run/docker.sock` and `/nix` from the host.
- `network_mode: host` is intentionally not enabled for the agent so it can still reach `woodpecker-server:9000` over the Compose network.
