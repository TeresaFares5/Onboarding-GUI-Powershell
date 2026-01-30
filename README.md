# Onboarding GUI (PowerShell + WPF)

A **sanitised, onboarding tool** written in PowerShell using WPF.

This project demonstrates how to build a real-world internal IT tool while following **security, configuration management, and automation best practices**.

---

##  What this project shows

This repository showcases:

- A **PowerShell WPF GUI** (no external UI frameworks required)
- Config-driven onboarding (company, office, department, groups, licenses)
- Automatic generation of:
  - Email address
  - UPN
  - Group membership
  - License defaults
- Separation of **code vs environment-specific configuration**
- A **Demo Mode** so the tool can run without Active Directory or Microsoft 365 access
- Enterprise-style flow with validation, confirmation, progress updates, and logging

This is intentionally designed to reflect how onboarding tooling is built in real corporate environments.

---

##  Security & Sanitisation (Important)

- **No real tenant IDs, domains, servers, OUs, or group names are committed**
- All organisation-specific values are loaded from `config/config.json`
- **`config/config.json` is excluded via `.gitignore`**
- Only `config/config.example.json` (placeholder values) is committed

> The real configuration never belongs in source control.

---

##  Repository structure

```
Onboarding-GUI-PowerShell/
│
├─ src/
│   └─ Onboarding-GUI.ps1
│
├─ config/
│   └─ config.example.json
│
├─ .gitignore
├─ README.md
└─ LICENSE
```

---

##  Quick start (Demo Mode)

Demo Mode allows anyone to run the GUI **without**:
- Active Directory
- Microsoft Graph
- Exchange Online

### 1. Create a local config file
```powershell
copy config\config.example.json config\config.json
```

### 2. Run the script in Demo Mode
```powershell
pwsh -ExecutionPolicy Bypass -File .\src\Onboarding-GUI.ps1 -DemoMode
```

In Demo Mode:
- No users are created
- No groups or licenses are assigned
- The UI simulates the full onboarding flow and logs what *would* happen

---

##  How the tool works

### Configuration-driven design
All environment-specific logic lives in `config.json`, including:
- Companies and domains
- Offices and address data
- Department mappings
- Default group memberships
- Default license sets

The script itself never contains hardcoded organisational data.

### Demo Mode vs Real Mode

| Mode | Behaviour |
|------|----------|
| Demo Mode | Simulates onboarding actions only |
| Real Mode | Executes AD, Microsoft Graph, and Exchange commands |

Demo Mode exists so the project can be reviewed, run, and tested safely on any machine.

---

## Real environment usage (not included)

To use this tool in a real environment you would:

- Install RSAT (ActiveDirectory module)
- Install Microsoft Graph PowerShell SDK
- Install ExchangeOnlineManagement
- Populate `config/config.json` with real values
- Run the script **without** `-DemoMode`

Real provisioning logic is intentionally scaffolded to avoid exposing production patterns or credentials.

---

## What I would add in production

If this were deployed internally, the next steps would include:

- Secure secrets handling (Key Vault / Secret Store)
- Robust retry logic for mailbox provisioning
- SKU-to-license mapping via Microsoft Graph
- Audit logging and error telemetry
- RBAC-based execution controls

---

