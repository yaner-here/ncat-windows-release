# Portable Ncat for Windows

Unofficial build of the Ncat source in this fork of nmap/nmap. The networking
utility is Nmap Ncat, not the separate traditional netcat implementation.

Download `ncat.exe` or the ZIP with licenses and build records from
[Releases](https://github.com/yaner-here/ncat-windows-release/releases). Every
successful **Ncat portable Windows** Actions run also provides a
`ncat-windows-x86-portable` artifact. Copy `ncat.exe` wherever you need it. It is a
native x86 executable, also usable on x64 Windows through WOW64. Windows 10/11
are the intended targets; older Windows versions have not been tested.

OpenSSL 3.5.9, its default and legacy providers, Lua, nbase, nsock, and the MSVC
runtime are statically linked. Windows system DLLs remain required. No Npcap,
OpenSSL DLLs, legacy.dll, OpenSSL installation, or VC redistributable is needed.

```powershell
.\ncat.exe --version
.\ncat.exe example.com 9999
.\ncat.exe --ssl --ssl-servername example.com example.com 9999
```

As with upstream Ncat, `--ssl` alone does not verify the peer certificate.
For certificate verification, supply your trusted PEM certificates explicitly:

```powershell
.\ncat.exe --ssl-verify --ssl-trustfile trusted-ca.pem example.com 443
```

Certificates, private keys, and Lua scripts supplied to relevant options are
user inputs. They are not embedded in this binary. The upstream ca-bundle.crt
is not distributed beside the executable in this artifact.

`build-info.json` records source commits, compiler runtime choice, runner image,
and the executable SHA-256. `dependencies.txt` records PE imports. `tests.json`
records TCP/UDP, TLS client/server, SNI, explicit certificate verification and
Lua smoke tests. Tests copy only the EXE into an empty runtime directory and
point OPENSSL_MODULES to a nonexistent directory to expose hidden DLL needs.

To rebuild, run the workflow on branch `ncat-portable`. Dependencies and Actions
are pinned to commits. The runner label is windows-2022; its image can change,
so bit-for-bit reproducibility is not promised. The scripts adapt upstream
Static project configurations in the CI checkout and select MSVC v143.

This artifact retains upstream licensing: see NMAP-LICENSE.txt,
OPENSSL-LICENSE.txt, and LUA-LICENSE.txt, plus the full source in this repository.
