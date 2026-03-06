# GitHub Actions CI/CD

This directory contains GitHub Actions workflows for continuous integration and deployment.

## Workflows

### `ci.yml` - Continuous Integration

**On pull request:** Runs format check only, then notifies the Feishu group (Bot A). Users reply and @mention the integration-test bot (Bot B) to get an interactive card and run the integration test on the private host. Results are reported to the Feishu group (and optionally to Bot A webhook and GitHub PR).

**On push** (to main/master/develop): Runs integration tests and build on GitHub in addition to format check.

#### Jobs

1. **Format check** (runs first on every push and PR)
   - Runs `cargo fmt --check` and `cargo clippy` (infini-router, infini-babysitter, infini-registry)
   - Fails on format or lint issues

2. **Notify Lark** (PR only, after format check)
   - Sends a PR notification to the Feishu group via Bot A webhook: repo, PR number, format check status, and a note to reply and @mention the integration-test bot to run integration test on the private host.
   - Repository secrets: **FEISHU_BOT_WEBHOOK**, **FEISHU_BOT_SIGNKEY** (optional), **FEISHU_AT_BOT_OPEN_ID** (optional, for @mention in the message).

3. **Integration Tests** (push only)
   - Same as before: Rust build, conda env, full integration test suite on GitHub runners.
   - Timeout: 15 minutes.

4. **Build** (push only)
   - Builds each binary in a matrix and uploads artifacts (retention: 1 day).

Integration test on the private host is triggered by the user via the Feishu bot (Bot B) card, not by the workflow. See the FeishuBot repo, use case **infinilm-svc-ci**, for server and card setup.

## Requirements

### Integration Tests

The integration tests require:
- Rust stable toolchain
- Python 3.10
- Conda (Miniconda) with conda-forge channel
- Python packages: `aiohttp`, `requests`

### Ports Used

The integration tests use the following ports:
- `8900`: Router
- `8901`: Registry
- `6001-6006`: Mock services and babysitters

Make sure these ports are available in the CI environment.

## Local Testing

To test the CI workflow locally, you can use [act](https://github.com/nektos/act):

```bash
# Install act
brew install act  # macOS
# or download from https://github.com/nektos/act/releases

# Run the integration tests job
act -j integration-tests

# Run all jobs
act
```

## Troubleshooting

### Integration Tests Fail

1. Check the logs in the workflow output
2. Verify all binaries are built successfully
3. Check that Python dependencies are installed
4. Ensure ports are not in use
5. Review the test script output for specific failures

### Build Failures

1. Check Rust toolchain version
2. Verify Cargo.lock is up to date
3. Check for dependency conflicts
4. Review compiler errors

### Lint Failures

1. Run `cargo fmt` locally to fix formatting
2. Run `cargo clippy` locally to fix linting issues
3. Address all warnings before pushing
