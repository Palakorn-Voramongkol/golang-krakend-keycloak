# Keycloak Production Configuration

This guide walks you through preparing and configuring Keycloak in **production** mode, tailored for both **Linux** and **Windows** Docker Compose environments.

---

## Table of Contents

- [Keycloak Production Configuration](#keycloak-production-configuration)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Prerequisites](#prerequisites)
  - [Generate or Obtain TLS Certificates](#generate-or-obtain-tls-certificates)
    - [Linux](#linux)
    - [Windows](#windows)
  - [Directory Layout](#directory-layout)
  - [Docker Compose Service Definition](#docker-compose-service-definition)
    - [Linux Mount](#linux-mount)
    - [Windows Mount](#windows-mount)
  - [Environment Variables](#environment-variables)
  - [Keycloak Command-Line Flags](#keycloak-command-line-flags)
  - [File \& Directory Permissions](#file--directory-permissions)
    - [Linux](#linux-1)
    - [Windows](#windows-1)
  - [Reverse Proxy Considerations](#reverse-proxy-considerations)
  - [Troubleshooting](#troubleshooting)

---

## Overview

In production mode, Keycloak enforces:

- **HTTPS-only** by default  
- **Strict hostname validation**  
- **Robust DB connectivity**  

We’ll cover certificate setup, hostname, Docker Compose, and common pitfalls on **both Linux and Windows**.

---

## Prerequisites

- Docker 20.10+ and Docker Compose 1.29+  
- PostgreSQL for Keycloak (container or managed)  
- OpenSSL (for cert generation) or access to CA-issued certs  
- Basic familiarity with your OS’s file system and permissions

---

## Generate or Obtain TLS Certificates

### Linux

```bash
mkdir -p keycloak/certs
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout keycloak/certs/tls.key \
  -out keycloak/certs/tls.crt \
  -subj "/CN=localhost"
````

* Outputs to `keycloak/certs/tls.crt` and `tls.key`.

### Windows

**Option 1: Git Bash / WSL (OpenSSL installed)**

```bash
mkdir -p keycloak/certs
openssl req -x509 -nodes -days 365 ^
  -newkey rsa:2048 ^
  -keyout keycloak/certs/tls.key ^
  -out keycloak/certs/tls.crt ^
  -subj "/CN=localhost"
```

**Option 2: PowerShell New-SelfSignedCertificate**
This creates a PFX; you’ll then export to PEM:

```powershell
# Create in user store
$cert = New-SelfSignedCertificate -DnsName "localhost" -CertStoreLocation "Cert:\CurrentUser\My" -NotAfter (Get-Date).AddYears(1)

# Export to PFX
$pw = ConvertTo-SecureString -String "password" -Force -AsPlainText
Export-PfxCertificate -Cert "Cert:\CurrentUser\My\$($cert.Thumbprint)" -FilePath .\keycloak\certs\tls.pfx -Password $pw

# Convert PFX → PEM
openssl pkcs12 -in keycloak/certs/tls.pfx -nocerts -nodes -passin pass:password > keycloak/certs/tls.key
openssl pkcs12 -in keycloak/certs/tls.pfx -clcerts -nokeys -passin pass:password > keycloak/certs/tls.crt
```

---

## Directory Layout

```
.
├── docker-compose.yml
├── keycloak/
│   ├── import-realm.json
│   └── certs/
│       ├── tls.crt
│       └── tls.key
└── kong/
    └── kong.yml
```

All paths are relative to your project root.

---

## Docker Compose Service Definition

Add this block under `services:` in `docker-compose.yml`:

```yaml
keycloak:
  image: quay.io/keycloak/keycloak:21.1.1
  container_name: keycloak_prod
  depends_on:
    - keycloak-db
  environment:
    DB_VENDOR: postgres
    DB_ADDR: keycloak-db
    DB_DATABASE: keycloak
    DB_USER: keycloak
    DB_PASSWORD: secret
    KC_HOSTNAME: localhost
    KC_HOSTNAME_STRICT: "true"
    KEYCLOAK_ADMIN: admin
    KEYCLOAK_ADMIN_PASSWORD: admin
    KC_HTTPS_CERTIFICATE_FILE: /opt/keycloak/certs/tls.crt
    KC_HTTPS_CERTIFICATE_KEY_FILE: /opt/keycloak/certs/tls.key
  command:
    - start
    - "--import-realm"
    - "--http-enabled=false"
    - "--hostname=localhost"
    - "--hostname-strict=true"
  volumes:
    # see below for OS-specific mounts
  ports:
    - "8443:8443"
```

### Linux Mount

```yaml
  volumes:
    - ./keycloak/import-realm.json:/opt/keycloak/data/import/realm.json:ro
    - ./keycloak/certs:/opt/keycloak/certs:ro
```

### Windows Mount

```yaml
  volumes:
    - ./keycloak/import-realm.json:/opt/keycloak/data/import/realm.json:ro
    - .\keycloak\certs:/opt/keycloak/certs:ro
```

> Docker for Windows will interpret the `.\` path correctly when using Linux containers.

---

## Environment Variables

| Variable                                    | Purpose                             |
| ------------------------------------------- | ----------------------------------- |
| `DB_VENDOR=postgres`                        | Use Postgres                        |
| `DB_ADDR=keycloak-db`                       | Postgres service host               |
| `DB_DATABASE=keycloak`                      | Database name                       |
| `DB_USER`, `DB_PASSWORD`                    | DB credentials                      |
| `KC_HOSTNAME`                               | Public hostname (must match TLS CN) |
| `KC_HOSTNAME_STRICT=true`                   | Enforce hostname check              |
| `KEYCLOAK_ADMIN`, `KEYCLOAK_ADMIN_PASSWORD` | Initial admin account               |
| `KC_HTTPS_CERTIFICATE_FILE`                 | Path to `tls.crt` inside container  |
| `KC_HTTPS_CERTIFICATE_KEY_FILE`             | Path to `tls.key` inside container  |

---

## Keycloak Command-Line Flags

| Flag                     | Description                      |
| ------------------------ | -------------------------------- |
| `start`                  | Production mode                  |
| `--import-realm`         | Import JSON realm on startup     |
| `--http-enabled=false`   | Disable HTTP, allow only HTTPS   |
| `--hostname=<your-host>` | Set Keycloak host for URL checks |
| `--hostname-strict=true` | Require matching `Host` header   |

---

## File & Directory Permissions

### Linux

```bash
chmod 0444 keycloak/certs/tls.crt
chmod 0444 keycloak/certs/tls.key
chown -R 1000:0 keycloak/certs
```

### Windows

1. Open File Explorer, navigate to `.../keycloak/certs`.
2. Right-click each file → **Properties** → **Security** tab.
3. Grant **Read** permission to your Docker host user or **Everyone**.
4. Ensure the folder and files are not blocked (Unblock if prompted).

---

## Reverse Proxy Considerations

If using NGINX/Apache/Kong as a TLS terminator:

1. Terminate TLS at the proxy.
2. Forward headers:

   ```
   X-Forwarded-For
   X-Forwarded-Proto
   X-Forwarded-Host
   ```
3. Adjust Keycloak flags:

   ```yaml
   - --http-enabled=true
   - --proxy=edge
   - --hostname-strict=false
   ```

---

## Troubleshooting

1. **HTTPS error**:

   ```
   ERROR: Key material not provided
   ```

   → Check cert file paths (`KC_HTTPS_CERTIFICATE_*`) and file permissions.

2. **Hostname mismatch**:

   ```
   Invalid Hostname
   ```

   → Verify `--hostname` and `KC_HOSTNAME` match your DNS or `/etc/hosts` entry.

3. **DB connection**:
   → Look in Postgres logs for refused connections; verify `DB_*` envs.

4. **Dev mode sanity check**:
   Temporarily revert command to:

   ```yaml
   command:
     - start-dev
     - "--import-realm"
   ```

   Ensure realm import & DB connectivity before re-adding production flags.

---

With these steps in place, you’ll have Keycloak running in production mode under HTTPS, with strict hostname validation and secure realm import—on **both Linux and Windows**.
