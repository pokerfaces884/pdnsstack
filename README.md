# pdns-stack (Experimental!!)

Podman Quadlet based PowerDNS stack for dnsdist, PowerDNS Recursor, NGN specific cache, Authoritative DNS, PowerAdmin, MariaDB, and weekly backup.

## Main design

- Single Podman network: `pdnsstack-net`
- Single Podman network in `.env.sample`: `192.0.2.0/24` RFC5737 TEST-NET-1 for documentation
- Internal IPv6 container subnet: `fd00:53::/64`
- Host-facing DNS service: `pdnsstack-dnsdist` on `53/udp` and `53/tcp`
- Initial authoritative DNS zone is configured by `PDNSSTACK_INITIAL_DOMAIN` in `.env`
- API / console / web secrets may be entered manually in `.env`; if left empty, `01-create.sh` auto-generates 20-character values using `openssl` and writes them back to `.env`
- `pdnsstack-cache-ngn` is automatically disabled when NGN IPv6 DNS variables are empty

## Usage

```bash
cp .env.sample .env
vi .env
chmod 600 .env
chmod +x scripts/*.sh

sudo ./scripts/01-create.sh
sudo ./scripts/02-deploy.sh
sudo ./scripts/03-startup.sh
sudo ./scripts/04-security-prepare.sh
sudo ./scripts/05-healthcheck.sh
sudo ./scripts/06-security-verify.sh
```

## Cleanup

```bash
sudo ./scripts/00-cleanup.sh
```

`00-cleanup.sh` removes only pdnsstack-related Quadlet files and generated services. It does not initialize or delete the whole `/etc/containers/systemd` directory. By default, it does not delete `${PDNSSTACK_BASE_DIR}/data` or `${PDNSSTACK_BASE_DIR}/backup`.
