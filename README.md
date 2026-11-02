# GuardLMS for Canvas

[![CI](https://github.com/LdesignMedia/canvas-guardlms/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/LdesignMedia/canvas-guardlms/actions/workflows/ci.yml)
[![Ruby](https://img.shields.io/badge/Ruby-3.1%2B-CC342D.svg)](guardlms_canvas.gemspec)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Connect your self-hosted Canvas installation to [GuardLMS](https://guardlms.com)
and keep its software inventory up to date.**

The plugin reports your Canvas revision, registered server plugins and Ruby/Rails
versions once a day. Connect through Canvas's native administration interface,
preview the reported data and check when GuardLMS last accepted an inventory.

[Installation](#installation) · [Connect in Canvas](#connect-in-canvas) · [Scheduling](#scheduling) · [Troubleshooting](#troubleshooting) · [Documentation](#documentation)

## Features

- Daily Canvas and registered server-plugin inventory using Canvas background jobs.
- One-click connection to GuardLMS with encrypted inventory-key storage.
- Connection status, key expiry, last attempt, last accepted inventory and component count.
- Manual push, payload preview and disconnect controls in Canvas.
- Automatic retries with backoff and protection against overlapping pushes.
- Manual inventory keys and environment overrides for managed deployments.

## Requirements

- **Self-hosted Canvas** with access to its deployment, Gemfile and background workers.
  This Rails engine cannot be installed in Instructure-hosted Canvas as an LTI app.
- Ruby **3.1 or later**, using the Ruby, Rails and Bundler versions required by your
  Canvas release. CI covers Ruby 3.3/Rails 7.1, Ruby 3.1/Rails 7.2 and Ruby 3.4/Rails 8.0; see
  [compatibility and validation](docs/development.md).
- A Canvas site administrator with **Manage site settings** permission.
- A GuardLMS account, a canonical HTTPS Canvas URL and outbound HTTPS access to GuardLMS.
- A GuardLMS API and dashboard with
  [Canvas integration support](https://github.com/LdesignMedia/guardlms/pull/2844) deployed.

The repository is private and the gem is not published to RubyGems. Install from
an authorized checkout using the steps below.

## Installation

1. Check out this repository on the Canvas server:

   ```bash
   git clone https://github.com/LdesignMedia/canvas-guardlms.git /opt/guardlms_canvas
   ```

   Authenticate with a GitHub account or deployment credential that can read this
   repository. Keep the checkout readable by the Canvas service user and available
   at the same path on each web and worker node.

2. In your Canvas checkout, add `Gemfile.d/guardlms.rb`:

   ```ruby
   gem "guardlms_canvas", path: "/opt/guardlms_canvas"
   ```

3. From the Canvas root, run `bundle install` using Canvas's Ruby and Bundler.
4. Restart Canvas web services **and background workers** so both load the engine.

No Canvas core patch or database migration is required. For repeatable deployments,
pin the connector checkout to a reviewed commit and deploy it with Canvas.

## Connect in Canvas

1. Sign in as a site administrator and open **Site Admin → Plugins → GuardLMS**
   using the gear icon. You can also visit `/plugins/guardlms/manage`.
2. Enter the **Canonical Canvas URL**, for example `https://canvas.example.com`,
   and click **Save settings**. Use the public HTTPS URL registered in GuardLMS.
3. Click **Connect to GuardLMS**, sign in to GuardLMS and approve the connection.
4. Return to Canvas and confirm **Connected**, a **Last accepted inventory** time
   and a **Reported components** count. The plugin sends its first inventory immediately.
5. Open the website in the [GuardLMS dashboard](https://dashboard.guardlms.com)
   and check **Tech Stack** for the reported components.

Canvas exchanges a single-use connection code for a website-bound inventory key,
stores that key using Canvas's encrypted plugin settings and publishes the supplied
ownership verification meta tag. You do not need to copy a key into Canvas.

Use **Preview reported data** to inspect the inventory without sending it, or
**Push now** to send a fresh inventory. The preview excludes credentials and plugin
settings. If the first push fails, check the status message and
[troubleshooting](#troubleshooting).

Use a separate connection for each installation or environment. Before starting
workers on a cloned installation, configure its own canonical URL and inventory key.

## Scheduling

After connection, **Enable reporting** and **Automatically report inventory daily**
are enabled. Canvas's periodic worker checks every **five minutes** and sends the
next inventory **24 hours after a successful push**. Keep Canvas background workers
running; no additional cron entry is needed.

Failed requests retry after five minutes, doubling up to six hours. A rejected key
(HTTP 401/403) pauses automatic retries until you reconnect or complete a successful
manual push. The settings page shows the last attempt and last accepted inventory;
a previous success alone does not confirm that workers are currently healthy.

For a deployment-time push or an external scheduler, run from the Canvas root:

```bash
RAILS_ENV=production bundle exec rake guardlms:push
```

The command prints the accepted component count and exits nonzero on failure or
when reporting is disabled, disconnected or already running. If you use an external
scheduler, clear **Automatically report inventory daily** while leaving **Enable
reporting** selected. Schedule on one node. See
[advanced settings](docs/advanced-settings.md) for environment overrides and key management.

## What it reports

| Inventory | Details |
| --- | --- |
| Canvas | The revision reported by the running installation |
| Registered server plugins | Plugin IDs, versions and enabled state from Canvas's plugin registry |
| Runtime | Ruby and Rails versions |
| Server | Application OS distribution/version and CPU architecture; optional configured web-server signature |
| Database | PostgreSQL server version from the existing Canvas database connection |
| Website | Canonical Canvas URL and inventory generation timestamp |

Unknown versions remain unknown; update availability is not checked. If Canvas
exposes no revision, its core version is `null` and the push adds no Canvas core
row to the stored inventory. Tech Stack still identifies Canvas from its authenticated
inventory, with the version shown as unknown. External LTI apps and installed Ruby gems are not enumerated.
One connector reports the whole installation, rather than a separate inventory
for each Canvas account.

This release provides inventory reporting. Browser analytics, JavaScript/server
error monitoring, security configuration auditing and a Canvas-specific advisory
catalog are outside its current scope.

## Privacy

Inventory is sent over HTTPS using a website-bound key. TLS certificate verification
is enabled and redirects are refused. Learner records, course records, plugin
settings, credentials and absolute filesystem paths are not collected.

Use **Preview reported data** before sending if you need to review the payload.
See the [inventory and data handling reference](docs/inventory.md) for fields,
limits and how GuardLMS replaces previous inventory.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| GuardLMS is missing from Plugins | Confirm the gem path and `Gemfile.d/guardlms.rb`, run `bundle install`, then restart web services and workers. |
| The settings page is unavailable | Use a site administrator account with **Manage site settings**, rather than an account administrator. |
| Connect is disabled | The key is managed through `GUARDLMS_API_KEY`. Use the manual connection or remove that override and restart web services and workers. |
| Connection expired or settings changed | Save the intended settings, then start **Connect to GuardLMS** again in the same signed-in Canvas session. |
| Reconnect required / key refused | Reconnect to obtain a new key, or replace the manually managed key. Check its expiry in GuardLMS. |
| Inventory is rejected | Check the canonical URL against the website registered in GuardLMS and review the [inventory limits](docs/inventory.md#limits-and-unknown-values). |
| Connection or TLS failure | Check outbound HTTPS access and the server's trusted CA certificates; confirm the API origin is correct. |
| First push works, but daily reports stop | Check Canvas background workers and both reporting checkboxes. Inspect the last attempt and any status error. |
| Unknown versions or updates | These can be expected: only versions exposed by Canvas's plugin registry are reported, and update availability is not checked. |

For self-hosted GuardLMS, manual keys, key renewal, disconnecting and uninstalling,
see [advanced settings](docs/advanced-settings.md).

## Documentation

- [Connection, configuration, key renewal and uninstalling](docs/advanced-settings.md)
- [Inventory, privacy and payload reference](docs/inventory.md)
- [Development, tests and compatibility](docs/development.md)

## Support and license

Report problems through [GitHub issues](https://github.com/LdesignMedia/canvas-guardlms/issues).
Include your Canvas revision, Ruby/Rails versions and the sanitized status message.
Keep inventory keys and connection callback URLs out of issue reports.

Licensed under [MIT](LICENSE). Maintained by [LdesignMedia](https://ldesignmedia.nl).
