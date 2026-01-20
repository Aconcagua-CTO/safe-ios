#pragma once

// TangemSdk expects this Clang module to exist:
// `import TangemSdk_secp256k1`
//
// This umbrella header exposes the subset of secp256k1 headers that TangemSdk's
// Swift interface references.

#include "secp256k1_ecdh.h"
#include "secp256k1_recovery.h"
#include "secp256k1_preallocated.h"
#include "secp256k1_schnorrsig.h"
#include "secp256k1_extrakeys.h"
#include "secp256k1_tangem.h"

