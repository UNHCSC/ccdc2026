# UNH CCDC/NECCDC 2026 Scripts

This repo contains cybersecurity related scripts for the 2026 NECCDC Regionals.

## Downloading Scripts

### Linux/Unix

The below command will download the latest script release and unzip it in your current directory on unix-like systems:

```shell
curl -s https://api.github.com/repos/UNHCSC/ccdc2026/releases/latest | awk -F \" '/zipball/ {print $(NF - 1)}' | xargs curl -L -o scripts.zip && unzip scripts.zip -d .
```

### Windows

On Windows you can use this command to download the scripts and extract them:

```powershell
powershell -c "Invoke-WebRequest -Uri (Invoke-RestMethod -Uri  https://api.github.com/repos/UNHCSC/ccdc2026/releases/latest).zipball_url -OutFile scripts.zip; Expand-Archive -Path .\scripts.zip -DestinationPath ."
```