# Ncat Windows Release

[![Windows build](https://github.com/yaner-here/ncat-windows-release/actions/workflows/ncat-portable.yml/badge.svg)](https://github.com/yaner-here/ncat-windows-release/actions/workflows/ncat-portable.yml)

> [!WARNING]
> Unofficial, portable Windows builds of [Nmap Ncat](https://nmap.org/ncat/).

Download `ncat.exe` from [Releases](https://github.com/yaner-here/ncat-windows-release/releases).
The x86 executable also runs on x64 Windows through WOW64. OpenSSL, its default
and legacy providers, Lua, and the MSVC runtime are statically linked; only
Windows system DLLs are required.

```powershell
.\ncat.exe example.com 9999
.\ncat.exe --ssl --ssl-servername example.com example.com 9999
```

For certificate verification, use `--ssl-verify --ssl-trustfile trusted-ca.pem`.

Run **Ncat portable Windows** in the Actions tab to rebuild. The workflow uses a
pinned vcpkg revision to install OpenSSL 3.6.5 with static libraries and runtime,
then builds the upstream Visual Studio projects:

```bat
vcpkg install openssl:x86-windows-static
```

Point `OpenSSLDir` at `vcpkg\installed\x86-windows-static`:

```bat
msbuild ncat\ncat.vcxproj /m /p:Configuration=Static /p:Platform=Win32 /p:PlatformToolset=v143 /p:OpenSSLDir=C:\path\to\openssl
```

Local builds require an x86 MSVC developer prompt and static OpenSSL headers and
libraries under `OpenSSLDir`; see the workflow for dependency setup.
Only `ncat.exe` is uploaded. Source and dependency licenses remain in this
repository and in the linked OpenSSL source release.

---

Nmap [![Build Status](https://github.com/nmap/nmap/actions/workflows/build.yml/badge.svg)](https://github.com/nmap/nmap/actions/workflows/build.yml)
====

Nmap is released under a custom license, which is based on (but not compatible
with) GPLv2. The Nmap license allows free usage by end users, and we also offer
a commercial license for companies that wish to redistribute Nmap technology
with their products. See [Nmap Copyright and Licensing](https://nmap.org/book/man-legal.html)
for full details.

The latest version of this software as well as binary installers for Windows,
macOS, and Linux (RPM) are available from
[Nmap.org](https://nmap.org/download.html)

Full documentation is also available
[on the Nmap.org website](https://nmap.org/docs.html).

Questions and suggestions may be sent to
[the Nmap-dev mailing list](https://nmap.org/mailman/listinfo/dev).

Installing
----------
Ideally, you should be able to just type:

    ./configure
    make
    make install

For far more in-depth compilation, installation, and removal notes, read the
[Nmap Install Guide](https://nmap.org/book/install.html) on Nmap.org.

Using Nmap
----------
Nmap has a lot of features, but getting started is as easy as running `nmap
scanme.nmap.org`. Running `nmap` without any parameters will give a helpful
list of the most common options, which are discussed in depth in [the man
page](https://nmap.org/book/man.html). Users who prefer a graphical interface
can use the included [Zenmap front-end](https://nmap.org/zenmap/).

Contributing
------------
Information about filing bug reports and contributing to the Nmap project can
be found in the [HACKING](HACKING) and [CONTRIBUTING.md](CONTRIBUTING.md)
files.
