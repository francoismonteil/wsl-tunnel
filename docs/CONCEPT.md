# Concept

## Why This Project Exists

The original question is simple:

How do developers running services and containers inside WSL2 consume dependencies that still live on Windows?

The tricky part is that WSL2 networking modes can improve one flow while degrading another.

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

## Why A Tunnel Helps

When the missing path is:

- WSL2 or a container inside WSL2 needs to call a service hosted on Windows

an SSH reverse tunnel gives an explicit fallback:

```text
Windows -> WSL2 via SSH
creates
WSL localhost:<wslPort> -> Windows localhost:<windowsPort>
```

That lets code inside WSL2 consume a Windows dependency through a stable local port, even when the native network mode is not sufficient.

## Why This Project Uses A Guided CLI

The tunnel itself is not novel. The difficulty is operational:

- developers forget ports
- developers mistype SSH flags
- developers do not know which tunnel is active
- multi-tunnel setups become confusing very quickly

So this project wraps the workaround in a guided CLI and a versioned service catalog.

## What This Project Is Not

This is not a replacement for native WSL2 networking when native networking already solves the problem.

This is also not a production service mesh or a high-throughput proxy.

It is a local-development workaround for cases where:

- the built-in networking options are partially helpful
- but still leave an important dependency path broken
