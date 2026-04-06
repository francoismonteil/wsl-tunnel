# Concept

This document belongs to the "responses explored" part of the repository.
It compares candidate response shapes for mixed-mode Windows + WSL2 + Docker
Engine constraints; it is not a blanket recommendation for the tunnel workflow.

## Why This Project Exists

The original question is simple:

How do developers running services and containers inside WSL2 consume dependencies that still live on Windows?

The tricky part is that WSL2 networking modes can improve one flow while degrading another.

This repository therefore treats the subject first as a mixed-mode Windows +
WSL2 + Docker Engine investigation, and only secondarily as a tunnel workflow
for one targeted unsupported path.

## What The Validation Shows

The validation matrix in this repository shows a pattern that can happen on constrained workstations:

- NAT can keep Windows -> published Docker ports working
- but NAT may still leave WSL2 unable to consume Windows-hosted services
- mirrored mode can improve native Windows <-> WSL2 communication
- but mirrored mode can break Windows -> Docker published ports

So the problem is not simply:

- "WSL2 cannot talk to Windows"

It is closer to:

- "No single built-in networking mode may satisfy all required local development flows at once."

## One Targeted Response: A Tunnel

When the missing path is:

- WSL2 or a container inside WSL2 needs to call a service hosted on Windows

an SSH reverse tunnel can provide one explicit fallback:

```text
Windows -> WSL2 via SSH
creates
WSL localhost:<wslPort> -> Windows localhost:<windowsPort>
```

That lets code inside WSL2 consume a Windows dependency through a stable local
port, even when the native network mode is not sufficient for that specific flow.

This repository does not claim that a tunnel should be the first answer to every
mixed-mode problem. It is one targeted mechanism included for cases where a
precise dependency path remains uncovered after broader mode, proxy, and
architecture tradeoffs have been evaluated.

## Why This Project Uses A Guided CLI

The tunnel itself is not novel. The difficulty is operational:

- developers forget ports
- developers mistype SSH flags
- developers do not know which tunnel is active
- multi-tunnel setups become confusing very quickly

So this repository includes a guided CLI and a versioned service catalog for that
targeted workaround.

## What This Project Is Not

This is not a replacement for native WSL2 networking when native networking already solves the problem.

This is also not a production service mesh or a high-throughput proxy.

It includes a local-development workaround for cases where:

- the built-in networking options are partially helpful
- but still leave an important dependency path broken
