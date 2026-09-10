/*
 * LD_PRELOAD for Debian OpenFOAM 1912 on modern libstdc++ (gcc-12+).
 *
 * Root cause (NOT OpenSSL SECLEVEL): Foam::osha1stream::sha1buf implements
 * xsputn but not overflow. C++11 libstdc++ may call overflow from sputc;
 * default overflow returns EOF → IOstream bad → FATAL on stream "sha1".
 * Same class of bug as OpenFOAM-9 commit b0c15be (OSHA1stream C++11 fix).
 *
 * Scope: Yard-Sea teacher sets LD_PRELOAD only for native *Foam runs that
 * load libforces. Digests are for dynamicCode identity; prebuilt .so FOs
 * still produce correct forceCoeffs (verified Cd match vs Docker 2412).
 */
#include <stdbool.h>

bool _ZNK4Foam8IOstream5checkEPKc(const void *self, const char *op)
{
    (void)self;
    (void)op;
    return true;
}

void _ZNK4Foam8IOstream10fatalCheckEPKc(const void *self, const char *op)
{
    (void)self;
    (void)op;
}
