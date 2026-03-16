# Contributing to wt-tools

Thanks for your interest in contributing!

## How to Contribute

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-change`)
3. Make your changes
4. Test on your platform (macOS/Linux for `.sh`, Windows for `.ps1`)
5. Submit a pull request

## Guidelines

- Keep scripts POSIX-compatible where possible (bash scripts)
- Test changes on both bash and zsh if modifying shell scripts
- PowerShell scripts should work on PowerShell 5.1+ and PowerShell Core
- Update both the Windows (`README.md`) and macOS (`README-macos.md`) docs if your change affects both platforms

## Reporting Issues

Open a GitHub issue with:
- Your OS and shell version
- Steps to reproduce the problem
- Expected vs actual behavior
