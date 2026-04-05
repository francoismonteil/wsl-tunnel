# Example: Multi-port setup

This example shows how to run multiple catalog services simultaneously from WSL.

## Services on Windows

- API: Windows:8443 (HTTPS)
- Jobs: Windows:8080 (HTTP)
- Cache: Windows:6379 (Redis-like)
- Database: Windows:5432 (PostgreSQL-like)

## Start all tunnels

```powershell
.\wsl-tunnel.ps1 up api
.\wsl-tunnel.ps1 up jobs
.\wsl-tunnel.ps1 up redis
.\wsl-tunnel.ps1 up postgres
```

All tunnels run independently and simultaneously.

## Test from WSL

```bash
# API calls
$ curl -k https://localhost:18443/api/status
API is up

# Job submission
$ curl -X POST http://localhost:18080/jobs/submit \
  -H "Content-Type: application/json" \
  -d '{"jobName":"reconciliation"}'
Job queued

# Cache access
$ redis-cli -h localhost -p 16379
redis> PING
PONG

# Database query
$ psql -h localhost -p 15432 -U user -d mydb
mydb=> SELECT 1;
 ?column?
----------
        1
```

## Monitor tunnels

From PowerShell:

```powershell
.\wsl-tunnel.ps1 status
.\wsl-tunnel.ps1 status api
```

## Stop selective tunnels

```powershell
# Stop only jobs tunnel
.\wsl-tunnel.ps1 down jobs

# Stop the remaining tunnels
.\wsl-tunnel.ps1 down api
.\wsl-tunnel.ps1 down redis
.\wsl-tunnel.ps1 down postgres
```

---

**Key takeaway:** Each tunnel is independent and identified by service name, not by manual port entry.
