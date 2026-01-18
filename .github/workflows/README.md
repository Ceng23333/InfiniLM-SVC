# GitHub Actions CI/CD

This directory contains GitHub Actions workflows for continuous integration and deployment.

## Workflows

### `ci.yml` - Continuous Integration

Runs on every push and pull request to `main`, `master`, and `develop` branches.

#### Jobs

1. **Integration Tests**
   - Sets up Rust toolchain (stable)
   - Sets up Python 3.10 with Miniconda
   - Creates conda environment `infinilm-integration-test`
   - Installs Python dependencies (aiohttp, requests)
   - Builds all three Rust binaries:
     - `infini-router`
     - `infini-babysitter`
     - `infini-registry`
   - Runs full integration test suite
   - Timeout: 15 minutes (test timeout: 120 seconds)

2. **Lint**
   - Runs `cargo fmt --check` to verify code formatting
   - Runs `cargo clippy` to check for linting issues
   - Fails on warnings

3. **Build**
   - Builds each binary separately in a matrix
   - Uploads binaries as artifacts (retention: 1 day)
   - Verifies all binaries compile successfully

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
