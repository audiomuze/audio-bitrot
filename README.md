# audio-bitrot

Small shell utilities for audio conversion and compression workflows.

## Overview

This repository contains lightweight Bash scripts focused on batch-friendly audio processing tasks. The scripts are designed to be simple to run from a terminal and easy to adapt for personal media workflows.

## Core Features

- Fast shell-based tooling with no application UI overhead.
- Script-focused workflow for repeatable audio processing tasks.
- Straightforward command-line usage suitable for automation.

## Included Scripts

- `tflac.sh`: helper script for FLAC-related processing/conversion tasks.
- `twavpack.sh`: helper script for WavPack-related processing/compression tasks.

## Usage

Run scripts directly from the project folder:

```bash
chmod +x tflac.sh twavpack.sh
./tflac.sh
./twavpack.sh
```

Use `-h` or `--help` if supported by a script to view available options.

## Requirements

- Linux/macOS shell environment (Bash)
- Any audio tools expected by the scripts (installed and available on `PATH`)

## Notes

These scripts are intentionally minimal and can be tailored to your own codec settings, naming rules, and folder layout.
