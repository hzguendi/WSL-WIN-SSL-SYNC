# WSL Windows Certificate Sync

## Description
This script (`cert-wsl.sh`) facilitates the synchronization of Windows certificates with WSL (Windows Subsystem for Linux). It exports certificates from Windows using PowerShell and imports them into WSL to ensure seamless certificate management across environments.

## License
This project is licensed under the **Apache 2.0 License**.

## Features
- Extracts Windows certificates and converts them for WSL use
- Automates the certificate import process in WSL
- Uses PowerShell for Windows-side operations
- Supports custom domain specifications

## Requirements
- **WSL (Windows Subsystem for Linux)** installed and configured
- **PowerShell** available on the Windows system
- **Root privileges** for importing certificates in WSL
- **OpenSSL** for debugging certificate issues

## Installation
1. Copy the script to a directory in WSL:
   ```sh
   cp cert-wsl.sh /usr/local/bin/
   chmod +x /usr/local/bin/cert-wsl.sh
   ```
2. Ensure PowerShell is accessible in WSL via `/mnt/c/WINDOWS/System32/WindowsPowerShell/v1.0/powershell.exe`.

## Usage
Run the script with appropriate arguments:
```sh
WIP
```

### Arguments
WIP

### Examples
WIP

## Debugging
To debug, you can check the extracted certificates and validate them with OpenSSL:
```sh
openssl x509 -in /usr/local/share/ca-certificates/windows/cert.pem -noout -text
```

Enable debugging mode by running:
```sh
bash ./cert-wsl.sh [actionflag] -d|-v
```
Check logs for errors or permission issues.

## To-Do
- **Optional**: Specify a source directory for certificates (defaulting to the root CA directory).
- **Do not migrate expired certificates**.
- **Check all certificate validity before copying**.
- Improve error handling and user feedback.

## Contributing
If you would like to contribute, fork the repository and submit a pull request with improvements or bug fixes.

