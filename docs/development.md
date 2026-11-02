# Development and compatibility

[Back to README](../README.md)

## Compatibility

The gem requires Ruby **3.1 or later**. Use the Ruby, Rails and Bundler versions
supported by the target Canvas release.

| CI runtime | Coverage |
| --- | --- |
| Ruby 3.1 / Rails 7.2 | Connector and lifecycle tests, engine smoke test, gem build |
| Ruby 3.3 / Rails 7.1 | Connector and lifecycle tests, engine smoke test, gem build |
| Ruby 3.4 / Rails 8.0 | Connector and lifecycle tests, engine smoke test, gem build |

The engine smoke test uses a minimal Canvas registry double. These combinations
do not constitute a promise of compatibility with every Canvas release; test
installation, connection and worker reporting against your target deployment.

## Local checks

From this repository, using Ruby 3.1 or later:

```bash
gem install minitest -v '~> 5.0' --no-document
gem install railties -v '~> 7.2.0' --no-document
for test in test/*_test.rb; do ruby "$test" --no-plugins || exit 1; done
gem build guardlms_canvas.gemspec
```

For the Rails 8.0 matrix, use Ruby 3.4 and install `railties` with `~> 8.0.0`
instead. CI runs all three combinations and builds the gem with its controllers and
templates. The repository is private; CI does not publish a RubyGem.

Tests cover inventory collection and transport, callback state, single-use sessions,
settings changes, retry backoff, overlapping jobs, disconnect races and sanitized
failures. See the [CI workflow](../.github/workflows/ci.yml) and [tests](../test).

## Real Canvas validation

The companion GuardLMS repository includes a
[Docker harness](https://github.com/LdesignMedia/guardlms/tree/main/integrations/canvas/docker)
for testing real Canvas against the GuardLMS receiver. Follow that directory's
README for its pinned Canvas revision and setup requirements.

Before deploying a new connector or Canvas revision, check:

1. The native Plugins entry and administrator-only settings page load.
2. Browser connection completes and the first inventory is accepted.
3. Payload preview matches the installed revision and plugin registry.
4. Manual push and the native periodic worker update the accepted inventory time.
5. Disconnect stops reporting, and reconnect restores it.

The GuardLMS API and dashboard require
[Canvas integration support](https://github.com/LdesignMedia/guardlms/pull/2844).
Keep test keys and disposable harness credentials out of commits and issue reports.
