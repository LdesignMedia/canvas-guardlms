# GuardLMS for self-hosted Canvas

A Rails engine connector for issue [#1995](https://github.com/LdesignMedia/guardlms/issues/1995),
using the same authenticated inventory-push model as Moodle `local_guardlms`.

Reports the Canvas revision, registered Canvas plugin IDs/versions/enabled state,
and Ruby/Rails versions. No plugin settings, learner records, course records,
credentials or absolute filesystem paths are collected. A plugin's enabled flag
is Canvas's `enabled?` result; it does not indicate whether the GuardLMS cron task
is configured. Plugins without a version and Canvas builds without a `VERSION`
file report null, rather than an invented version.

This initial connector targets **self-hosted Canvas**. It is not an LTI tool and
cannot be installed into Instructure-hosted Canvas. It has no browser connect UI,
SDK injection, configuration auditing, gem inventory or Canvas plugin advisory
catalog. External LTI applications are not Canvas registered server plugins and
are not enumerated. Updates remain “not checked” in GuardLMS.

## Repository and development

The repository starts private. The RubyGem is not published automatically.
CI tests Ruby 3.1 with Rails 7.2 and Ruby 3.4 with Rails 8.0, then builds the gem.
The companion GuardLMS receiver must be deployed before distributing the plugin.

## Install

Deploy the GuardLMS API changes before installing the connector.

1. Copy this directory to a stable path on the Canvas server, for example
   `/opt/guardlms_canvas` (readable by the Canvas service user).
2. Add `Gemfile.d/guardlms.rb` in the Canvas checkout:

   ```ruby
   gem "guardlms_canvas", path: "/opt/guardlms_canvas"
   ```

3. Run `bundle install` using the Ruby/Bundler version required by that Canvas
   checkout. Restart Canvas services and check `bundle exec rake -T guardlms`
   lists `guardlms:push`. No Canvas core patch or database migration is needed.
4. Register and verify the canonical Canvas website in GuardLMS. Using an
   authorized GuardLMS session or API key with `websites:write`, call
   `POST /api/websites/{website_id}/inventory-key` with JSON
   `{"platform":"canvas"}`. Store the returned `data.token` securely; it is shown
   only once. Use `data.siteurl` as the canonical URL. Issuing a new inventory key
   revokes the website's previous inventory keys. Note `data.expires_at` for rotation.
5. Configure these environment variables in the Canvas service account's secret
   environment (never in source control or the cron command):

   ```text
   GUARDLMS_SITE_URL=https://canvas.example.com
   GUARDLMS_API_KEY=<website-bound inventory key>
   GUARDLMS_API_URL=https://api.guardlms.com
   ```

   `GUARDLMS_API_URL` is optional and must be an HTTPS origin without a path,
   credentials, query or fragment. The connector always uses
   `/api/externalpush/canvas`. It verifies TLS and never follows redirects.
   Set a separate URL and key for each cloned/staging installation. A single
   connector reports the installation, not separate inventories per Canvas account.
6. From the Canvas root, with that environment loaded, run:

   ```sh
   RAILS_ENV=production bundle exec rake guardlms:push
   ```

   Confirm “GuardLMS inventory accepted” and inspect the website's technology
   inventory in GuardLMS. Then schedule that command daily on **one node**, using
   your scheduler's environment/secret injection and working-directory settings.
   For a systemd timer, set `WorkingDirectory` to the Canvas root, `User` to the
   Canvas service user and `EnvironmentFile` to a protected configuration file.
   Use the installation's absolute `bundle` executable in `ExecStart`.

## Operations

The command exits nonzero on failure, so connect scheduler failures to your
existing operations alerts. Success is logged without the payload or key.
HTTP 401/403 requires a valid replacement inventory key; 422 means check the
canonical site URL and payload. Network errors, 429 and 5xx leave the previous
inventory intact; retry on the next run. Redirects are configuration errors:
configure the actual API origin instead of a redirecting hostname. The client
uses 10-second connect and 30-second read/write timeouts with no automatic retry.

Collection failure aborts the entire push. The receiver requires a complete
plugin list and replaces the Canvas inventory atomically. Scanner inventory and
other connectors' components are preserved. The last accepted push supplies the
existing GuardLMS freshness indicator; this does not prove that scheduled runs
are healthy indefinitely.

To disconnect, disable the scheduled task and revoke the key in GuardLMS. Remove
the gem entry, run `bundle install`, and restart Canvas to uninstall. Existing
inventory remains historical and follows GuardLMS's normal stale-data rules.

## Development and validation

```sh
gem install minitest -v '~> 5.0'
ruby test/connector_test.rb --no-plugins
gem install railties -v '~> 7.2.0' --no-document
ruby test/engine_smoke_test.rb --no-plugins
gem build guardlms_canvas.gemspec
```

Backend tests live in [`ExternalPushCanvasTest.php`](https://github.com/LdesignMedia/guardlms/blob/main/backend/tests/Feature/Api/ExternalPushCanvasTest.php) in the
GuardLMS repository. Ruby unit tests stub the Canvas plugin API and HTTP transport;
they do not replace installation testing against the target Canvas release.
A [Docker integration harness](https://github.com/LdesignMedia/guardlms/tree/main/integrations/canvas/docker) also verifies this connector
inside real Canvas against the GuardLMS receiver, including the scheduled task
and TLS/authentication failure paths.

The extension points were checked against upstream Canvas:
[Gemfile.d loading](https://github.com/instructure/canvas-lms/blob/master/Gemfile),
[engine example](https://github.com/instructure/canvas-lms/blob/master/gems/plugins/moodle_importer/lib/moodle_importer/engine.rb),
[plugin metadata API](https://github.com/instructure/canvas-lms/blob/master/lib/base/canvas/plugin.rb),
and [Canvas.revision](https://github.com/instructure/canvas-lms/blob/master/lib/base/canvas.rb).
