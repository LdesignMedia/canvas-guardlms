# Inventory and data handling

[Back to README](../README.md)

## Reported fields

The connector reads Canvas's plugin registry and runtime versions. It does not
inspect course content or enumerate external LTI applications or installed gems.

| Field | Source / meaning |
| --- | --- |
| `siteurl` | Configured canonical HTTPS Canvas URL |
| `generatedtime` | Inventory generation time as Unix seconds |
| `canvas.version` | `Canvas.revision`, which may be a revision identifier rather than a release number |
| `canvas.plugins[].id` | Registered Canvas server-plugin ID |
| `canvas.plugins[].version` | Version exposed by that plugin, or `null` if absent |
| `canvas.plugins[].enabled` | Plugin's enabled state |
| `ruby.version` | Running Ruby version |
| `rails.version` | Running Rails version |
| `server` | OS family, distribution ID/name/version/description, architecture and optional configured web-server signature |
| `database.version` | PostgreSQL server version read with `SHOW server_version` |

Example payload, with illustrative versions and a placeholder timestamp:

```json
{
  "siteurl": "https://canvas.example.com",
  "generatedtime": 1793577600,
  "canvas": {
    "version": "your-canvas-revision",
    "plugins": [
      { "id": "guardlms", "version": "0.2.0", "enabled": true }
    ]
  },
  "ruby": { "version": "3.4.12" },
  "rails": { "version": "8.0.5" }
}
```

Use **Preview reported data** on the settings page for the current installation's
payload. Preview collects the inventory without pushing it or including the key.
It requires the same site administrator permission as the settings page.

## Limits and unknown values

- Up to **2,000 registered plugins** per inventory.
- Plugin IDs must contain **1–120 characters** and be unique regardless of case.
  Missing, oversized or duplicate IDs fail collection locally; no partial list is sent.
- Canvas and plugin versions up to **100 characters**.
- Ruby and Rails versions up to **50 characters**.
- Canonical site URL up to **255 characters**.

Missing or blank versions become `null`. If Canvas exposes no revision, GuardLMS
does not persist a Canvas core row from the push. The dashboard can still identify
Canvas from authenticated inventory without guessing its release. Metadata exceeding the connector
limits fails collection before a request is sent; receiver validation can reject
the payload separately. The connector does not check available updates; unknown
versions and update availability must not be treated as evidence of being up to date.

One connection reports an installation from its default shard. It does not create
a separate inventory for each Canvas account.

## Transport and storage

Inventory is sent to `POST /api/externalpush/canvas` on the configured API origin
with Bearer-token authentication. The key is bound to the GuardLMS website. TLS
certificate verification remains enabled and redirects are refused.

HTTP connection/read/write timeouts are **10/30/30 seconds**, with a **45-second**
overall HTTP request limit. Error messages avoid echoing remote response bodies or
credentials into Canvas status messages. The settings and preview responses use
`Cache-Control: no-store`.

GuardLMS atomically replaces the previous Canvas inventory with a complete accepted
snapshot, removing plugins that are no longer present while preserving records
owned by other connectors. Older snapshots are ignored. The connector treats a
stale response as a failed attempt, preserves the last accepted time and component
count, and asks the administrator to check the Canvas clock. The receiver rejects
generation timestamps more than one hour in the future, so keep the Canvas server
clock synchronized.

## Privacy and scope

The payload includes the registered website URL, software identifiers, versions,
enabled state and collection time. It excludes learner and course records, plugin
settings, credentials and absolute filesystem paths. Browser connection also
exchanges a single-use code and publishes the supplied ownership verification meta
tag in Canvas page metadata. The inventory key is stored using Canvas's encrypted
plugin settings unless supplied through the server environment.

This version does not inject a browser monitoring SDK, capture JavaScript or server
errors, collect page analytics, audit security configuration, enumerate gems or
provide a Canvas-specific advisory catalog.

OS metadata describes the application environment (including a container when
used), rather than the physical host. Only allowlisted `/etc/os-release` fields
are read, with a 16 KiB input limit. No hostnames, database names, connection
strings or credentials are reported. Optional metadata is omitted if unavailable.

Set `GUARDLMS_WEBSERVER` to a known fronting server signature, for example
`nginx/1.24.0`. The connector does not infer a server version from a client gem
or assume the reverse proxy is running inside the Canvas container. Update this
setting when the proxy is upgraded.
