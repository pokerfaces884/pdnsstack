# pdns-stack

Podman Quadlet based PowerDNS stack for dnsdist, PowerDNS Recursor, NGN specific cache, Authoritative DNS, PowerAdmin, MariaDB, and weekly backup.

## Main design

- Single Podman network: `pdnsstack-net`
- Internal container subnet: `172.30.0.0/24` and `fd00:53::/64`
- Host-facing DNS service: `pdnsstack-dnsdist` on `53/udp` and `53/tcp`
- Direct monitoring/debug ports are published on `HOST_IPV4`
- `pdnsstack-cache-ngn` is automatically disabled when `NGN_DNS_IPV6_1` and `NGN_DNS_IPV6_2` are empty

## Host exposed ports

- `53/udp,tcp`: dnsdist DNS
- `3306/tcp`: MariaDB
- `10053/udp,tcp`: cache-int DNS
- `10080/tcp`: cache-int REST API
- `10054/udp,tcp`: cache-ngn DNS, only when NGN is enabled
- `10081/tcp`: cache-ngn REST API, only when NGN is enabled
- `11053/udp,tcp`: pdns-auth DNS
- `11080/tcp`: pdns-auth REST API
- `12080/tcp`: PowerAdmin HTTP

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

By default `00-cleanup.sh` does not delete `${BASE_DIR}/data` or `${BASE_DIR}/backup`.
# pdnsstack
