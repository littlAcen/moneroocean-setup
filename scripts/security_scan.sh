#!/bin/bash
#
# Security Scanning Script
# Run dependency and code security scans
#

set -e

echo "=================================="
echo "Security Dependency Scan"
echo "=================================="
echo ""

# Check if we're in a virtual environment
if [ -z "$VIRTUAL_ENV" ]; then
    echo "WARNING: Not running in a virtual environment"
    echo "Consider running: python3 -m venv venv && source venv/bin/activate"
    echo ""
fi

# Install security scanning tools if needed
echo "[1/5] Installing security scanning tools..."
pip install -q pip-audit safety bandit 2>/dev/null || echo "Some tools may already be installed"

# Python dependency vulnerability scan with pip-audit
echo ""
echo "[2/5] Running pip-audit (checks for known vulnerabilities)..."
pip-audit || echo "pip-audit found vulnerabilities - review above output"

# Python dependency vulnerability scan with safety
echo ""
echo "[3/5] Running safety check..."
safety check || echo "safety found vulnerabilities - review above output"

# Python code security scan with bandit
echo ""
echo "[4/5] Running bandit (static security analysis)..."
bandit -r . -ll -f txt || echo "bandit found security issues - review above output"

# Go vulnerability scan (if go is installed)
echo ""
echo "[5/5] Running Go vulnerability scan..."
if command -v go &> /dev/null; then
    if [ -f "go.mod" ]; then
        echo "Installing govulncheck..."
        go install golang.org/x/vuln/cmd/govulncheck@latest
        echo "Running govulncheck..."
        govulncheck ./... || echo "govulncheck found vulnerabilities - review above output"
    else
        echo "No go.mod found - skipping Go scan"
    fi
else
    echo "Go not installed - skipping Go scan"
fi

echo ""
echo "=================================="
echo "Security scan complete!"
echo "=================================="
echo ""
echo "Next steps:"
echo "1. Review any vulnerabilities found above"
echo "2. Update dependencies: pip install --upgrade -r requirements.txt"
echo "3. Run: go get -u ./... (for Go dependencies)"
echo "4. Re-run this script to verify fixes"
