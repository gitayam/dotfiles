# Bash Functions Docker Test Suite

This directory contains a comprehensive Docker-based testing framework for all Linux bash functions. The tests ensure that all functions work correctly in a clean Ubuntu 22.04 environment with all necessary dependencies.

## Quick Start

### Prerequisites
- Docker and Docker Compose installed
- At least 2GB free disk space
- Internet connection for downloading dependencies

### Running Tests

1. **Build and run all tests:**
   ```bash
   cd /Users/sac/Documents/Git/dotfiles/linux/tests
   docker-compose up --build bash-function-tests
   ```

2. **Run tests interactively:**
   ```bash
   docker-compose run --rm bash-function-tests bash
   # Inside container:
   ./tests/run_tests.sh
   ```

3. **Run specific test modules:**
   ```bash
   docker-compose run --rm bash-function-tests bash tests/test_utils.sh
   docker-compose run --rm bash-function-tests bash tests/test_security.sh
   ```

4. **Performance testing:**
   ```bash
   docker-compose run --rm bash-function-tests bash tests/performance_test.sh
   ```

## Test Structure

### Main Test Scripts
- **`run_tests.sh`** - Main test orchestrator with HTML reporting
- **`test_all.sh`** - Runs all module tests with summary
- **`performance_test.sh`** - Performance and timing tests

### Module Test Scripts
- **`test_utils.sh`** - Tests utility functions (calc, findex, extract, etc.)
- **`test_security.sh`** - Tests security functions (encryption, virus scan, etc.)
- **`test_transfer.sh`** - Tests file transfer functions (rsync, wormhole, etc.)
- **`test_handle_files.sh`** - Tests file processing (images, PDF, OCR, etc.)
- **`test_network.sh`** - Tests network functions (port scan, connectivity, etc.)
- **`test_system.sh`** - Tests system monitoring functions
- **`test_developer.sh`** - Tests development tools and Git functions
- **`test_docker.sh`** - Tests Docker management functions
- **`test_apps.sh`** - Tests application aliases and shortcuts
- **`test_aws.sh`** - Tests AWS CLI functions
- **`test_encryption.sh`** - Tests encryption and cryptographic functions

## Test Coverage

### Tested Function Categories
1. **Utility Functions**: File operations, calculations, archives
2. **Security Functions**: Encryption, virus scanning, secure deletion
3. **Transfer Functions**: File synchronization, HTTP sharing, cloud upload
4. **File Handling**: Image processing, OCR, PDF manipulation
5. **Network Functions**: Connectivity checks, port scanning, DNS lookup
6. **System Functions**: Monitoring, process management, system info
7. **Developer Tools**: Git operations, code statistics, backup
8. **Docker Functions**: Container management, compose operations
9. **AWS Functions**: Cloud resource management (requires credentials)
10. **Encryption**: GPG, OpenSSL, Age, Base64 operations

### Dependencies Tested
- **Core Tools**: bash, curl, wget, git, bc, jq
- **Archive Tools**: tar, zip, unzip, 7zip
- **Network Tools**: nmap, netcat, traceroute, dig
- **Image Tools**: ImageMagick, exiftool, tesseract
- **Security Tools**: ClamAV, GPG, age, OpenSSL
- **Transfer Tools**: rsync, magic-wormhole, rclone
- **Development Tools**: Node.js, Python, AWS CLI

## Test Results

### Output Locations
- **Logs**: `test_logs/` directory with timestamped files
- **Reports**: `test_output/` directory with HTML reports
- **Artifacts**: Generated files for verification

### Report Types
1. **HTML Report**: Comprehensive test report with all details
2. **Console Output**: Real-time test progress and results
3. **Individual Logs**: Per-test detailed logs
4. **Performance Metrics**: Timing and resource usage data

## Advanced Usage

### Custom Test Configuration
```bash
# Test with specific timeout
TIMEOUT=60 docker-compose run --rm bash-function-tests bash tests/run_tests.sh

# Test with debug output
DEBUG=1 docker-compose run --rm bash-function-tests bash tests/test_utils.sh

# Test specific functions only
docker-compose run --rm bash-function-tests bash -c "
  source ~/.bash_utils
  calc '2 + 2'
  findex /tmp -name '*.txt'
"
```

### Network Testing
```bash
# Test network functions with host networking
docker-compose up network-test
```

### Volume Mounting for Development
The compose file mounts bash function files as read-only volumes, allowing you to:
- Edit functions on the host
- Test immediately without rebuilding
- Debug issues in real-time

## Troubleshooting

### Common Issues
1. **Docker permission errors**: Ensure Docker daemon is running
2. **Network timeouts**: Some tests require internet connectivity
3. **Missing tools**: Container includes all dependencies, but some may fail silently
4. **AWS tests fail**: Requires proper AWS configuration

### Debug Mode
```bash
# Enable verbose output
bash -x tests/test_utils.sh

# Check container environment
docker-compose run --rm bash-function-tests bash -c "
  env | grep -E '(PATH|HOME|USER)'
  which bash
  bash --version
"
```

### Manual Testing
```bash
# Enter container for manual testing
docker-compose run --rm bash-function-tests bash

# Inside container:
source ~/.bash_utils
ls -la ~/.bash_*
echo 'Testing manual function execution...'
```

## Expected Results

### Success Criteria
- ✅ All core functions load without errors
- ✅ Basic operations work (file manipulation, calculations)
- ✅ Security functions handle encryption/decryption
- ✅ Network functions can perform basic connectivity tests
- ✅ System monitoring functions return valid data

### Acceptable Warnings
- ⚠️ Some tools may not be available (network-dependent)
- ⚠️ AWS functions require credentials
- ⚠️ Some system functions may have limited container access

### Test Statistics
- **Total Functions**: 100+ bash functions across 11 modules
- **Test Coverage**: Core functionality of all major features
- **Execution Time**: ~5-10 minutes for full suite
- **Container Size**: ~2GB with all dependencies

## Integration with CI/CD

This test suite can be integrated into continuous integration pipelines:

```yaml
# Example GitHub Actions
- name: Test Bash Functions
  run: |
    cd linux/tests
    docker-compose up --build --abort-on-container-exit bash-function-tests
```

## Next Steps

After running tests:
1. Review HTML report in `test_output/`
2. Check individual test logs for any failures
3. Run performance tests to ensure acceptable response times
4. Update function documentation based on test results
5. Add new tests for any new functions developed
