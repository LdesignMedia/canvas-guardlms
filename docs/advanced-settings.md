# Connection and advanced settings

[Back to README](../README.md)

## Canvas settings

Open **Site Admin → Plugins → GuardLMS** or `/plugins/guardlms/manage` as a site
administrator with **Manage site settings** permission.

| Setting | Purpose |
| --- | --- |
| Canonical Canvas URL | Public HTTPS URL registered in GuardLMS, for example `https://canvas.example.com` |
| Enable reporting | Allow manual and automatic pushes; clearing it stops both |
| Automatically report inventory daily | Allow the native Canvas worker to send daily inventory |
| Inventory key | Optional website-bound key for manual connection; leave blank to preserve the stored key |
| GuardLMS API origin | API HTTPS origin; defaults to `https://api.guardlms.com` |
| GuardLMS dashboard origin | Browser connection destination; defaults to `https://dashboard.guardlms.com` |

The last three fields are under **Advanced settings and manual inventory key**.
Stored keys are encrypted by Canvas and never displayed back in the form.

The site URL must use HTTPS without credentials, a query or a fragment. API and
dashboard URLs must additionally be origins without a path: do not append `/api`
or `/connect`. The settings URL limit is 255 characters.

Changing the stored site URL or API destination clears the stored connection.
Save the new settings and reconnect before sending inventory to the new target.

## Manual inventory key

Use one-click connection from the README for the normal setup. For a manually
managed installation:

1. Obtain a **website-bound Canvas inventory key** from your GuardLMS administrator.
   The website's canonical URL must match the URL Canvas reports. A general-purpose
   account API key is not a substitute.
2. Save the canonical URL and, for self-hosted GuardLMS, the API and dashboard origins.
3. Enter the key under **Advanced settings and manual inventory key**.
4. Select **Enable reporting** and, if desired, **Automatically report inventory daily**.
5. Click **Save settings**, then **Push now** and confirm the accepted inventory time.

Manual keys do not run the browser code exchange or obtain its ownership
verification token. Complete any required ownership verification in GuardLMS.
If no expiry is supplied, the settings page asks you to check your GuardLMS account.

## Environment overrides

These variables override the corresponding stored settings:

| Variable | Default | Purpose |
| --- | --- | --- |
| `GUARDLMS_SITE_URL` | Stored canonical URL | HTTPS Canvas URL registered in GuardLMS |
| `GUARDLMS_API_KEY` | Encrypted stored key | Website-bound inventory key |
| `GUARDLMS_API_URL` | `https://api.guardlms.com` | HTTPS API origin, without `/api` |
| `GUARDLMS_DASHBOARD_URL` | `https://dashboard.guardlms.com` | HTTPS dashboard origin for browser connection |

For example, configure these through your deployment's secret and environment management:

```dotenv
GUARDLMS_SITE_URL=https://canvas.example.com
GUARDLMS_API_KEY="your-website-bound-inventory-key"
GUARDLMS_API_URL=https://api.guardlms.com
GUARDLMS_DASHBOARD_URL=https://dashboard.guardlms.com
```

Only the site URL and key are necessary for an environment-managed deployment
using the default GuardLMS service. Do not commit keys to version control. Apply
the same environment to web services and workers, then restart both after changes.

An environment-managed key disables **Connect to GuardLMS**. Remove the override
and restart both processes before switching to browser connection. **Disconnect**
still stops reporting when an environment key is present; select **Enable reporting**
and save to resume it. An environment key is not deleted by disconnecting.

## Scheduling and retries

The native periodic job runs every five minutes. Successful pushes set the next
attempt for 24 hours later; there is no configurable fixed time of day. Failures
retry after 5, 10, 20 minutes and so on, capped at six hours. HTTP 401/403 blocks
automatic retries until reconnection or a successful manual push.

**Push now** and `guardlms:push` bypass the daily schedule and authentication-retry
pause. Both still require a key, enabled reporting and no active push lease.

For an external scheduler, turn off **Automatically report inventory daily**, keep
**Enable reporting** selected, and run this on one node from the Canvas root:

```bash
RAILS_ENV=production bundle exec rake guardlms:push
```

Avoid scheduling both the native worker and an external daily cron. A database-backed
lease prevents overlapping pushes; generation checks prevent a response from an
older request restoring connection state after settings change or disconnect.

## Key renewal and connection status

The settings page shows connection status, key expiry, last attempt, last accepted
inventory and component count. A supplied expiry in the past shows **Reconnect
required**. HTTP 401/403 also shows that status and stops automatic retries.

For browser-managed connections, click **Connect to GuardLMS** again and approve
the connection. For manual connections, obtain a replacement website-bound key,
update the stored key or `GUARDLMS_API_KEY`, and send a test push. Restart web
services and workers when changing environment variables.

## Cloned installations

Give each production, staging or development installation its own GuardLMS website,
canonical URL and key **before starting workers**. Changing the stored URL clears
the stored connection, but a copied canonical URL cannot automatically identify a
clone. Review both copied database settings and deployment environment overrides.

## Disconnect and uninstall

Click **Disconnect** to stop reporting and remove the locally stored key, connection
status and ownership verification token. This does not revoke the key in GuardLMS;
revoke it there as well if it must become unusable everywhere. Environment-managed
keys must also be removed from deployment secrets if you no longer need them.

To uninstall:

1. Disconnect in Canvas.
2. Remove `Gemfile.d/guardlms.rb` from the Canvas checkout.
3. Run `bundle install` using Canvas's Ruby and Bundler.
4. Restart Canvas web services and background workers on every node.
5. Remove the connector checkout when no deployed process uses it.

## Upgrading

Deploy the reviewed connector revision to the same path on every node, run
`bundle install` and restart web services and workers. Confirm that the settings
page loads, **Preview reported data** works and **Push now** records a new success.
