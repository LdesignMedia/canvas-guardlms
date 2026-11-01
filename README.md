# GuardLMS for self-hosted Canvas

A Rails engine using the same website-bound inventory push and browser connection
model as Moodle `local_guardlms`. Requires self-hosted Canvas; this is not an LTI
application for Instructure-hosted Canvas.

## Install and connect

Deploy the companion [GuardLMS changes](https://github.com/LdesignMedia/guardlms/pull/2844)
(API and dashboard) before using one-click connection.

1. Place this checkout at `/opt/guardlms_canvas`, readable by the Canvas service user.
2. Add `Gemfile.d/guardlms.rb` to the Canvas checkout:

   ```ruby
   gem "guardlms_canvas", path: "/opt/guardlms_canvas"
   ```

3. Run `bundle install` using Canvas's Ruby/Bundler, then restart Canvas web services
   **and background workers**. No core patch or database migration is required.
4. As a site administrator with **Manage site settings**, open **Site Admin → Plugins
   → GuardLMS** (the gear), or `/plugins/guardlms/manage`.
5. Save the canonical HTTPS Canvas URL, then click **Connect to GuardLMS**. Sign in
   to GuardLMS, approve the site, and return to Canvas. The plugin exchanges a
   single-use code, encrypts the inventory key using Canvas's own encrypted plugin
   settings, publishes the ownership verification meta tag, and pushes immediately.
6. Confirm **Connected**, the last accepted inventory, and the component count.
   Canvas's worker checks every five minutes and sends inventory once per day.

**Push now**, **Preview reported data**, and **Disconnect** are available on the same
page. The page shows last attempt/success, key expiry, errors and reporting status.
The preview never includes credentials or plugin configuration.

## Manual keys and server configuration

Alternatively, obtain a website-bound inventory key from GuardLMS and enter it under
**Advanced settings and manual inventory key**. Enable reporting and save. An empty
key field preserves the stored key. The key is never rendered back into the page.

Server environment overrides take precedence:

```text
GUARDLMS_SITE_URL=https://canvas.example.com
GUARDLMS_API_KEY=<website-bound inventory key>
GUARDLMS_API_URL=https://api.guardlms.com
GUARDLMS_DASHBOARD_URL=https://dashboard.guardlms.com
```

Only the site URL and a key are necessary for a wholly environment-managed deployment.
The API and dashboard values above are defaults; both must be HTTPS origins without
paths, credentials, queries or fragments. An environment-managed key disables the
browser Connect button. Disconnect still stops reporting until explicitly re-enabled.
Environment changes require restarting both web services and workers.

For diagnostics or an external scheduler, run from the Canvas root:

```sh
RAILS_ENV=production bundle exec rake guardlms:push
```

The command respects disabled/disconnected state, exits nonzero on failure, and does
not print credentials. Prefer the native worker schedule; avoid adding a second daily
cron. If using an external scheduler, turn off automatic reporting in the UI.

## Reliability and data scope

- Successful pushes schedule the next report after 24 hours. Transient failures
  retry after 5 minutes, doubling up to 6 hours. HTTP 401/403 stops automatic retries
  until reconnect or a successful manual push. Expiry is shown as reconnect required.
- A database-backed lease prevents overlapping pushes. Generation checks prevent an
  in-flight response from restoring state after settings change or disconnect.
- TLS verification stays enabled; redirects are refused. Connect/read/write limits
  are 10/30/30 seconds, with a 45-second overall HTTP request limit.
- Changing the stored Canvas URL or API destination clears the stored connection.
  For cloned installations, configure a separate canonical URL and key before
  starting workers. A copied canonical URL cannot automatically identify a clone.
- Disconnect clears local credentials and verification state. Revoke the key in
  GuardLMS as well if it must become unusable everywhere. Uninstall by removing the
  gem entry, running `bundle install`, and restarting web services and workers.

Reports Canvas revision, registered Canvas plugin IDs/versions/enabled state, and
Ruby/Rails versions. No learner records, course records, plugin settings, credentials
or absolute filesystem paths are collected. Unknown versions remain null and updates
remain “not checked”. A complete inventory replaces the previous Canvas inventory
atomically; other connectors' records are preserved.

This release does **not** yet implement Moodle's SDK injection, server error capture,
configuration auditing, gem inventory or a Canvas advisory catalog. External LTI apps
are not Canvas registered server plugins and are not enumerated. One connector reports
an installation, not separate inventories for each Canvas account. Last success does
not prove that the background worker is currently healthy.

## Development and validation

The repository is private; CI does not publish the RubyGem. CI tests Ruby 3.1/Rails 7.2
and Ruby 3.4/Rails 8.0, then builds the gem including controllers and templates.

```sh
gem install minitest -v '~> 5.0' --no-document
gem install railties -v '~> 7.2.0' --no-document
for test in test/*_test.rb; do ruby "$test" --no-plugins || exit 1; done
gem build guardlms_canvas.gemspec
```

The [Docker harness](https://github.com/LdesignMedia/guardlms/tree/feature-canvas-connector-1995/integrations/canvas/docker)
tests real Canvas against the GuardLMS receiver. Unit tests cover callback state,
single-use sessions, settings changes, backoff, overlapping jobs, disconnect races and
sanitized failures. Installation testing against your target Canvas release is still
required; the Rails engine smoke test uses a minimal Canvas registry double.
