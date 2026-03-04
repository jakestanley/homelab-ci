# homelab-ci

Woodpecker CI runs here as a long-running Docker Compose service.

Assumptions:
- Service identity is `ci`, matching `services.ci` in the sibling registry.
- The primary Woodpecker UI/API URL on the LAN is `https://ci.stanley.arpa`.
- The published Woodpecker port defaults to `20034` and is configured via `WOODPECKER_PORT`.
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
- `WOODPECKER_HOST`: Primary Woodpecker URL used on the LAN. Default is `https://ci.stanley.arpa`.
- `WOODPECKER_PORT`: Host port published for Woodpecker and used by `tailscale funnel`. Default is `20034`.
- `WOODPECKER_EXPERT_WEBHOOK_HOST`: Public webhook URL GitHub reaches. With Tailscale Funnel, set this to your device's `https://<device>.<tailnet>.ts.net` URL.
- `WOODPECKER_OPEN`: Leave this `false` normally. Temporarily set it to `true` only for first-login/bootstrap if closed registration blocks your admin login, then set it back to `false` and recreate `woodpecker-server`.
- `WOODPECKER_POLL_INTERVAL`: How often Woodpecker syncs repository metadata from GitHub. This does not replace GitHub webhooks for `push` events. `5m` is the default in this repo.
- `WOODPECKER_TOKEN`: Woodpecker personal access token for local helper scripts such as `scripts/add-repo.sh`.
- `GITHUB_CLIENT_ID`: GitHub OAuth client id.
- `GITHUB_CLIENT_SECRET`: GitHub OAuth client secret.
- `AGENT_SECRET`: Shared secret used by the Woodpecker server and agent.

## Start

```bash
./scripts/up.sh
```

`./scripts/up.sh` is idempotent. It installs Tailscale on the host if it is missing,
starts `tailscaled` when systemd is available, verifies the host is connected to the
tailnet, runs `docker compose up -d`, and ensures `tailscale funnel $WOODPECKER_PORT`
is active for the published host port.

If Tailscale is installed but not yet authenticated, `./scripts/up.sh` stops and tells
you to run `sudo tailscale up` once before re-running the script.

## Tailscale Funnel for webhooks

This keeps the Woodpecker UI/API on `https://ci.stanley.arpa` inside the network while
GitHub sends webhooks to the host's public Tailscale Funnel URL.

### Step by step

1. Make sure MagicDNS and HTTPS are enabled for the tailnet. Tailscale Funnel requires both.
2. Run:

```bash
./scripts/up.sh
```

3. If the script tells you the host is not connected to Tailscale yet, run:

```bash
sudo tailscale up
```

Complete the browser auth flow once, then rerun:

```bash
./scripts/up.sh
```

4. `./scripts/up.sh` will run `sudo tailscale funnel --bg $WOODPECKER_PORT` for you.
5. If Tailscale opens a browser or prints an approval URL, approve Funnel for the tailnet and this device.
6. Copy the public URL that `tailscale funnel status` shows. It will look like `https://<device>.<tailnet>.ts.net`.
   Tailscale DNS and HTTPS certificate provisioning can take up to 10 minutes after Funnel is first enabled, so a new Funnel URL may fail TLS checks briefly before it becomes usable.
7. In `.env`, keep `WOODPECKER_HOST=https://ci.stanley.arpa`.
8. In `.env`, set `WOODPECKER_EXPERT_WEBHOOK_HOST` to the public Tailscale Funnel URL from the previous step.
9. Recreate Woodpecker so it advertises the webhook URL GitHub can reach:

```bash
./scripts/up.sh
```

10. Refresh the repository webhook registration by re-running:

```bash
./scripts/add-repo.sh owner/repo
```

11. Verify the Funnel is still active:

```bash
tailscale funnel status
```

12. When testing the Funnel URL, prefer a device that is not on the same tailnet. A machine already on Tailscale may reach the device directly instead of exercising the public Funnel path.
13. Push a test commit to a branch and confirm a `push` pipeline appears in Woodpecker.

### Result

- LAN users continue to use `https://ci.stanley.arpa`.
- GitHub sends webhooks to the host's `https://<device>.<tailnet>.ts.net` Funnel URL.
- Woodpecker continues talking to GitHub and serving the UI on the internal host you already use.

## Activate a repository

Create a Woodpecker personal access token in your Woodpecker profile, add it to `.env` as
`WOODPECKER_TOKEN`, then activate a repo without using the UI:

```bash
./scripts/add-repo.sh owner/repo
```

The helper also enables trusted volume access for the repository so pipeline mounts work.
It also repairs the repository webhook configuration in Woodpecker, which is useful after
changing `WOODPECKER_EXPERT_WEBHOOK_HOST`.
That trust change requires a Woodpecker server admin token; if the token can activate repos
but cannot update trust, the script exits with an error after activation.
It also ensures five cron jobs exist on the default branch: every 15 minutes, every 30
minutes, every hour, every 6 hours, and every 24 hours.

You'll probably want the following repos as a minimum:
- homelab-infra
- nix

## Notes

- The agent uses the Docker backend and mounts the host Docker socket.
- `push` pipelines still require GitHub to deliver webhooks to Woodpecker. In this repo, the simplest public path is Tailscale Funnel on the Docker host plus `WOODPECKER_EXPERT_WEBHOOK_HOST`.
- Every pipeline step receives the host CA certificate from `/etc/homelab/certs/ca/ca.crt` at `/etc/ssl/certs/homelab-ca.crt`.
- Pipelines that `curl` homelab services using that CA should use `curl --cacert /etc/ssl/certs/homelab-ca.crt https://...` or set `CURL_CA_BUNDLE=/etc/ssl/certs/homelab-ca.crt`.
- The agent stores its config in the named volume `woodpecker-agent-config`.
- Existing GitHub repo webhooks may need to be refreshed after changing `WOODPECKER_EXPERT_WEBHOOK_HOST` so they point at the new public URL.
