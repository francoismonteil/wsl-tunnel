# Validation Matrix

This document captures the test cases used to validate whether WSL2 networking modes are sufficient on their own, and where they fall short for real development workflows.

The goal is not to prove a theory in advance. The goal is to record what actually works and what does not on constrained workstations.

## What We Are Validating

We care about four different communication paths:

1. Windows -> native process running in WSL2
2. Windows -> Docker container running inside WSL2
3. WSL2 native process -> service hosted on Windows
4. Docker container inside WSL2 -> service hosted on Windows

If a given WSL2 networking mode solves only some of these paths, then it does not fully solve the local development problem.

## Test Fixtures

Use simple, reproducible fixtures before testing any business application:

- Windows-hosted HTTPS service on `8443`
- Native WSL2 HTTP server on `4200`
- Docker container published as `8080:80` with `nginx:alpine`
- Optional app container published on `4200` when testing a real application stack
- Optional Elasticsearch container on `9200:9200` to confirm behavior on a realistic service

## Reference Commands

### Native WSL2 HTTP server

```bash
python3 -m http.server 4200 --bind 0.0.0.0
```

### Simple container in WSL2

```bash
docker run --rm -d --name test-nginx -p 8080:80 nginx:alpine
```

### Docker port check

```bash
docker ps
docker port test-nginx
```

Expected mapping:

```text
80/tcp -> 0.0.0.0:8080
```

### Windows access checks

```powershell
curl.exe http://localhost:4200
curl.exe http://localhost:8080
curl.exe -vk https://localhost:8443
```

### WSL2 access checks

```bash
curl http://localhost:4200
curl http://localhost:8080
curl -vk https://localhost:8443
```

### Container access checks

```bash
docker exec -it test-nginx sh
```

Inside the container:

```sh
apk add --no-cache curl
curl http://<wsl-service-endpoint>:4200
curl -vk https://localhost:8443
curl -vk https://<windows-host-endpoint>:8443
```

## Configuration Matrix

### Configuration A

```ini
[wsl2]
localhostForwarding=true
```

This is the NAT baseline with Windows localhost forwarding enabled.

### Configuration B

```ini
[wsl2]
networkingMode=mirrored
```

This is the mirrored networking mode.

## Observed Results

The table below records only what has already been explicitly validated.

| Flow | NAT + `localhostForwarding=true` | Mirrored | Notes |
|------|----------------------------------|----------|-------|
| Windows -> native WSL2 service | OK | OK | Native WSL2 app on `4200` is reachable from Windows in both tested modes. |
| Windows -> Docker published port | OK | KO | `nginx:alpine` published as `8080:80` is reachable from Windows in NAT, but not in mirrored mode. |
| WSL2 -> Docker published port | OK | OK | The published container remains reachable from inside WSL2. |
| Windows -> Windows service on `8443` | OK | Not part of the differentiator | The Windows service itself is healthy and reachable from Windows. |
| WSL2 -> Windows service via `localhost:8443` | KO | Not yet recorded in this matrix | In NAT, `localhost` from WSL2 does not reach the Windows host service. |
| WSL2 -> Windows service via Windows host IP | KO | Not yet recorded in this matrix | This was already tested and reported as non-working in the constrained NAT setup. |
| Container -> native WSL2 service | OK | Not yet recorded in this matrix | A containerized app was able to reach the Angular server running natively in WSL2. |
| Container -> Windows service on `8443` | KO | Not yet recorded in this matrix | A containerized app was not able to reach the Windows-hosted service. |

## Current Conclusions

### What NAT solves

- Windows can reach native WSL2 services
- Windows can reach published Docker ports in WSL2

### What NAT does not solve in the constrained setup

- WSL2 cannot reach the Windows-hosted service on `8443` using `localhost`
- WSL2 also cannot reach the same Windows-hosted service through the Windows host IP in the tested environment
- Containers inside WSL2 also fail to reach that Windows-hosted service

### What mirrored solves

- Windows can still reach native WSL2 services

### What mirrored breaks in the currently observed setup

- Windows can no longer reach published Docker ports in WSL2, even though:
  - the container is healthy
  - the port mapping is visible
  - the service remains reachable from inside WSL2

## Why This Matters

These observations suggest that neither tested WSL2 mode solves the full local development problem:

- NAT leaves WSL2 and its containers unable to reliably consume Windows-hosted services
- Mirrored improves native WSL2 connectivity, but breaks an important Windows -> container workflow

That gap is the reason this project still exists as a possible workaround.

## Remaining Checks

The matrix is already strong enough to justify the problem statement, but these checks would make the evidence even stronger:

1. Repeat the mirrored test with a second trivial container and a second port
2. Record whether a container in mirrored mode can reach the Windows `8443` service
3. Record whether the Windows-hosted `8443` service is reachable from native WSL2 in mirrored mode
4. Repeat the matrix on a second workstation to reduce the risk of a machine-specific conclusion

## Reporting Format

When recording a new workstation or a new configuration, use this format:

```text
Configuration:
- NAT + localhostForwarding=true
- or mirrored

Flows:
- Windows -> WSL native: OK / KO
- Windows -> Docker published port: OK / KO
- WSL -> Windows localhost service: OK / KO
- WSL -> Windows host IP service: OK / KO
- Container -> WSL native: OK / KO
- Container -> Windows service: OK / KO

Evidence:
- command used
- exact error or response
- port mapping shown by Docker
```
