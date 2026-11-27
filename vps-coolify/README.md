<!-- @format -->

# vps-coolify

[Coolify](https://coolify.io) (self-hosted PaaS on Docker + Traefik) through its official installer.

**Opt-in** (`config.default: false`), and an **alternative to `svc-k3s` and `vps-dokploy`**, not an addition: each runs a proxy that must own ports 80/443. `config.conflicts` makes `zz-setup` abort before any step starts when two are selected, and `up` itself refuses to run while k3s or Dokploy is installed.

Part of [`vps`](https://github.com/tomgrv/vps) · order 6.5 · opt-in · needs root, Ubuntu · cannot run with `svc-k3s` or `vps-dokploy` · [how steps work](../README.md#contributing).

## Usage

```bash
sudo vps-setup --with-vps-coolify      # add it to a full run
sudo vps-setup --only-vps-coolify      # just this step
sudo vps-setup --down-vps-coolify      # remove it
sudo zz-setup ./ -o vps-coolify         # without vps-setup, from a checkout
```

`up` runs the upstream installer (it installs Docker if missing and starts Coolify, its Postgres, Redis, realtime and proxy under `/data/coolify`), then re-applies `vps-security`'s private-ports guard. A re-run is safe: once Coolify is there the installer is **not** run again. Upgrade from Coolify's own UI.

## Access and security

- **Admin UI** on port `8000`, with realtime on `6001` and the terminal on `6002`, all declared `private`: `vps-security` opens them on the internal interface only, and the final summary prints `http://<internal-ip>:8000`. Set `SYSTEM_COOLIFY_ROOT_EMAIL` and `SYSTEM_COOLIFY_ROOT_PASSWORD` **together** (the installer skips a half-set pair) to predefine the admin; otherwise the first visit creates the admin account, so join the internal network before opening it.
- **Docker bypasses ufw.** `vps-security`'s `vps-private-ports-guard.service` drops DNAT-ed connections to every `private` port on the default-route interface, and `up` re-applies it once Docker runs. Check from outside the internal network: `curl -m 5 http://<public-ip>:8000` must time out. It needs `vps-security` (on by default). IPv4 only.
- **Apps** deployed through Coolify are served by its proxy on `80`/`443` (public). Any other port an app publishes is NAT-ed past ufw too: publish only what you mean to expose.

## Environment variables

Passed to the upstream installer under its own names.

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `SYSTEM_COOLIFY_ROOT_USERNAME` | no | _(empty)_ | Admin username created by the installer |
| `SYSTEM_COOLIFY_ROOT_EMAIL` | no | _(empty)_ | Admin email created by the installer |
| `SYSTEM_COOLIFY_ROOT_PASSWORD` | no | _(empty)_ | Admin password created by the installer |
| `SYSTEM_COOLIFY_DOCKER_ADDRESS_POOL_BASE` | no | _(empty)_ | Docker address pool base, e.g. `172.20.0.0/16`, to avoid clashing with a VPC |

## Ports and access

| Port   | Access  | What                                         |
| ------ | ------- | -------------------------------------------- |
| `80`   | public  | Coolify proxy HTTP, also for Lets Encrypt HTTP-01 |
| `443`  | public  | Coolify proxy HTTPS                          |
| `8000` | private | Coolify admin UI                             |
| `6001` | private | Realtime (websocket) service the UI uses     |
| `6002` | private | In-browser terminal                          |

## Removing (`down`)

`down` removes Coolify **and everything it deployed**: the managed containers, the `coolify*` volumes, the `coolify` network and `/data/coolify`. Docker itself is removed too (its installer put it there).

```bash
sudo vps-setup --down-vps-coolify
```

## Dependencies

It needs no other step, and conflicts with `svc-k3s` and `vps-dokploy`.

## Tests

```sh
bats test.bats
```

Static checks only (syntax, step shape, conflicts, ports): the install needs a live root Ubuntu box.
