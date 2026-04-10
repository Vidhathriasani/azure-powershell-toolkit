# Contributing

Contributions are welcome. Please follow these guidelines.

## How to Contribute

1. Fork the repository
2. Create a feature branch from `develop`: `git checkout -b feature/your-feature develop`
3. Write your code with proper comment-based help (synopsis, description, parameters, examples)
4. Add Pester tests for any new functions
5. Run `Invoke-ScriptAnalyzer -Path ./src -Recurse` and fix any issues
6. Run `Invoke-Pester ./tests/` and ensure all tests pass
7. Submit a pull request to the `develop` branch

## Code Standards

- Follow PowerShell approved verbs (`Get-Verb` for reference)
- Include full comment-based help with `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, and `.EXAMPLE`
- Use `[CmdletBinding()]` on all functions
- Support `-WhatIf` for any function that modifies resources
- Use `Write-Verbose` for debug output, `Write-Host` sparingly for user facing output
- Handle errors with try/catch and provide meaningful error messages

## Testing

- Write Pester 5.x tests for every public function
- Mock all Azure cmdlets in tests (no live Azure calls in CI)
- Aim for meaningful test coverage on business logic
- Tests should be runnable without an Azure connection

## Commit Messages

Use clear, descriptive commit messages:

- `feat: add certificate expiration monitoring`
- `fix: handle empty cost data response`
- `docs: update setup guide with service principal auth`
- `test: add tests for VPN gateway health check`
