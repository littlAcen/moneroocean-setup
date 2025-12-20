# Dependency Management Guide

This guide explains how to properly manage dependencies for this project.

## Quick Start

### Python Dependencies

1. **Create a virtual environment** (recommended):
```bash
python3 -m venv venv
source venv/bin/activate  # On Linux/Mac
# or
.\venv\Scripts\activate  # On Windows
```

2. **Install dependencies**:
```bash
pip install -r requirements.txt
```

3. **Verify installation**:
```bash
pip list
```

### Go Dependencies

1. **Initialize Go modules** (if not already done):
```bash
go mod download
```

2. **Update dependencies**:
```bash
go get -u ./...
go mod tidy
```

3. **Verify installation**:
```bash
go list -m all
```

## Security Scanning

Run the security scan script to check for vulnerabilities:

```bash
./scripts/security_scan.sh
```

This will:
- Check Python dependencies for known CVEs
- Scan code for security issues
- Check Go dependencies for vulnerabilities
- Provide remediation recommendations

## Updating Dependencies

### Python

```bash
# Update all packages to latest versions
pip install --upgrade -r requirements.txt

# Update specific package
pip install --upgrade paramiko

# Check for outdated packages
pip list --outdated
```

### Go

```bash
# Update all dependencies
go get -u ./...
go mod tidy

# Update specific dependency
go get -u github.com/shirou/gopsutil/v3@latest
```

## Dependency Security Best Practices

1. **Always pin versions** in requirements.txt and go.mod
2. **Run security scans** before deploying
3. **Update regularly** to get security patches
4. **Use virtual environments** to isolate dependencies
5. **Review dependency licenses** before adding new packages

## Critical Security Notes

### Python

- **pysftp is DEPRECATED** - Do not use. Migrate to paramiko's SFTP client:
  ```python
  # Old (pysftp - DEPRECATED)
  import pysftp
  with pysftp.Connection(host, username=user, private_key=key) as sftp:
      sftp.get(remote_path, local_path)

  # New (paramiko - RECOMMENDED)
  import paramiko
  ssh = paramiko.SSHClient()
  ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
  ssh.connect(host, username=user, key_filename=key)
  sftp = ssh.open_sftp()
  sftp.get(remote_path, local_path)
  sftp.close()
  ssh.close()
  ```

- **paramiko CVE-2023-48795** - Ensure version >= 3.4.0 to fix Terrapin Attack

### Go

- Always use versioned imports (v3 for gopsutil)
- Run `govulncheck` regularly

## Automated Security Scanning

### GitHub Actions (Recommended)

Add to `.github/workflows/security.yml`:

```yaml
name: Security Scan

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
  schedule:
    - cron: '0 0 * * 0'  # Weekly

jobs:
  python-security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      - name: Install dependencies
        run: pip install -r requirements.txt
      - name: Run pip-audit
        run: |
          pip install pip-audit
          pip-audit
      - name: Run bandit
        run: |
          pip install bandit
          bandit -r . -ll

  go-security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-go@v4
        with:
          go-version: '1.21'
      - name: Run govulncheck
        run: |
          go install golang.org/x/vuln/cmd/govulncheck@latest
          govulncheck ./...
```

## File Cleanup

To reduce repository bloat:

```bash
./scripts/cleanup_duplicates.sh
```

This script will:
- Identify duplicate files
- Show file sizes and counts
- Provide cleanup recommendations

**Note**: Review the script before executing deletions.

## Common Issues

### Issue: "ModuleNotFoundError: No module named 'X'"

**Solution**: Install dependencies:
```bash
pip install -r requirements.txt
```

### Issue: "go.mod not found"

**Solution**: Initialize Go modules:
```bash
go mod init github.com/yourusername/moneroocean-setup
go mod tidy
```

### Issue: Security vulnerabilities found

**Solution**:
1. Run `./scripts/security_scan.sh` to identify issues
2. Update affected packages: `pip install --upgrade <package>`
3. Re-run security scan to verify fix

## Resources

- [pip-audit documentation](https://pypi.org/project/pip-audit/)
- [safety documentation](https://pyup.io/safety/)
- [govulncheck documentation](https://pkg.go.dev/golang.org/x/vuln/cmd/govulncheck)
- [Python Virtual Environments](https://docs.python.org/3/library/venv.html)
- [Go Modules](https://go.dev/blog/using-go-modules)

## License Compliance

Before adding new dependencies, check their licenses:

```bash
# Python
pip install pip-licenses
pip-licenses

# Go
go install github.com/google/go-licenses@latest
go-licenses csv ./...
```

Ensure all dependencies are compatible with your project's license.
