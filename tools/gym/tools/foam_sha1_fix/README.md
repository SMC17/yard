# foam_sha1_fix — Debian OpenFOAM 1912 forceCoeffs LD_PRELOAD

## Problem

Native `libforces` / `forceCoeffs` on Debian OpenFOAM **1912** fatals:

```
FOAM FATAL IO ERROR: error in IOstream "sha1" ...
```

This is the **OSHA1stream / sha1buf::overflow** ABI bug with gcc-12+ libstdc++,
**not** an OpenSSL `SECLEVEL` / CipherString issue (`OPENSSL_CONF` does not help).

## Fix

`libfoam_sha1_check_bypass.so` interposes `Foam::IOstream::check` /
`fatalCheck` so the bad OSHA1stream does not abort. The Yard-Sea L3 teacher
sets `LD_PRELOAD` only for native solver invocations.

## Rebuild

```sh
gcc -shared -fPIC -O2 -o libfoam_sha1_check_bypass.so foam_sha1_check_bypass.c
```

## Manual use

```sh
export FOAM_ETC=/usr/share/openfoam/etc WM_PROJECT_DIR=/usr/share/openfoam
export LD_PRELOAD=/path/to/libfoam_sha1_check_bypass.so
simpleFoam
```
