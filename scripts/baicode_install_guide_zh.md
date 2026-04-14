# BAI code 安装指南

## 平台支持

| 操作系统 | 架构                           |
| -------- | ------------------------------ |
| macOS    | x86_64、arm64（Apple Silicon） |
| Linux    | x86_64                         |
| Windows  | x86_64（AMD64）                |

## 系统要求

- **Python 3.10 ~ 3.13**
- macOS / Linux：需要 `curl`
- Windows：需要 PowerShell 5.1+

---

## macOS / Linux

在终端中运行以下命令：

```sh
# 下载安装脚本
curl -fsSL https://raw.githubusercontent.com/BAI-labs/BAI-tools/refs/heads/main/scripts/baicode_install.sh -o baicode_install.sh

# 运行安装脚本
bash baicode_install.sh
```

安装过程会询问是否创建虚拟环境（`.venv`），输入 `y` 确认，或直接回车跳过。

---

## Windows

在 PowerShell 中运行以下命令：

```powershell
# 下载安装脚本
iwr -useb https://raw.githubusercontent.com/BAI-labs/BAI-tools/refs/heads/main/scripts/baicode_install.ps1 -OutFile baicode_install.ps1

# 运行安装脚本
.\baicode_install.ps1
```

安装过程会询问是否创建虚拟环境（`.venv`），输入 `y` 确认，或直接回车跳过。

> **注意：** 如果遇到执行策略限制，请先运行以下命令解除限制，然后重试：
>
> ```powershell
> Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
> ```

---

## 使用虚拟环境

安装时选择创建虚拟环境后，后续使用前需要先激活：

**macOS / Linux：**

```sh
source .venv/bin/activate
```

**Windows：**

```powershell
.\.venv\Scripts\Activate.ps1
```

---

## 常见问题

**Python 未找到**

请确认已安装 Python 3.10+，并可从终端访问：

```sh
python3 --version
```

如未安装，请从 [python.org](https://www.python.org/downloads/) 下载。

**pip 不可用**

```sh
python3 -m ensurepip --upgrade
```

**下载失败**

检查网络连接是否正常，以及是否能访问 `https://download.bankofai.io`。
