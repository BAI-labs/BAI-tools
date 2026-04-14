# BAI code Installation Guide

## Supported Platforms

| OS      | Architecture                  |
| ------- | ----------------------------- |
| macOS   | x86_64, arm64 (Apple Silicon) |
| Linux   | x86_64                        |
| Windows | x86_64 (AMD64)                |

## Requirements

- **Python 3.10 – 3.13**
- macOS / Linux: `curl`
- Windows: PowerShell 5.1+

---

## macOS / Linux

Run the following command in your terminal:

```sh
# Download install script
curl -fsSL https://raw.githubusercontent.com/BAI-labs/BAI-tools/refs/heads/main/scripts/baicode_install.sh -o baicode_install.sh

# run and install BAI code
bash baicode_install.sh
```

The installer will ask whether to create a virtual environment (`.venv`). Enter `y` to confirm, or press Enter to skip.

---

## Windows

Run the following command in PowerShell:

```powershell
# download install script
iwr -useb https://raw.githubusercontent.com/BAI-labs/BAI-tools/refs/heads/main/scripts/baicode_install.ps1 -OutFile baicode_install.ps1

# run and install BAI code
.\baicode_install.ps1
```

The installer will ask whether to create a virtual environment (`.venv`). Enter `y` to confirm, or press Enter to skip.

> **Note:** If script execution is blocked by the execution policy, run the following command first, then retry:
>
> ```powershell
> Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
> ```

---

## Using a Virtual Environment

If you chose to create a virtual environment during installation, activate it before use:

**macOS / Linux:**

```sh
source .venv/bin/activate
```

**Windows:**

```powershell
.\.venv\Scripts\Activate.ps1
```

---

## Troubleshooting

**Python not found**

Verify that Python 3.10+ is installed and accessible from your terminal:

```sh
python3 --version
```

If not installed, download it from [python.org](https://www.python.org/downloads/).

**pip not available**

```sh
python3 -m ensurepip --upgrade
```

**Download failed**

Check your network connection and verify that `https://download.bankofai.io` is reachable.
