# audio-bitrot

Small shell utilities for audio conversion and compression workflows.

## Overview

This repository contains lightweight Bash scripts focused on batch-friendly audio processing tasks. The scripts are designed to be simple to run from a terminal and easy to adapt for personal media workflows.

## Core Features

- Fast shell-based tooling with no application UI overhead.
- Script-focused workflow for repeatable audio processing tasks.
- Straightforward command-line usage suitable for automation.
- Resumable runs by default using per-path state files.
- Detailed logging for successful files, corrupted files, decode errors, and discovery errors.

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

By default, both scripts resume from existing state/log files in `/tmp`. Use `--fresh` to clear prior state and start a full new pass.

## Requirements

- Linux/macOS shell environment (Bash)
- Any audio tools expected by the scripts (installed and available on `PATH`)

