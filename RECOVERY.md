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
