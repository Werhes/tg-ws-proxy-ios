#ifndef RustBridge_h
#define RustBridge_h

#include <stdint.h>

// C ABI exposed by the Rust core (libtgwsproxy.a).

#ifdef __cplusplus
extern "C" {
#endif

/// Starts the local MTProto proxy.
/// Returns 0 on success, -1 if already running, -3 if bind failed.
int32_t StartProxy(const char *host, int32_t port, const char *dc_ips,
                   const char *secret, int32_t verbose);

/// Stops the running proxy. Returns 0 on success, -1 if not running.
int32_t StopProxy(void);

/// Sets the WebSocket pool size (2/4/6).
void SetPoolSize(int32_t size);

/// Sets the directory used for the cfproxy domains cache.
void SetCfProxyCacheDir(const char *cacheDir);

/// Enables/disables Cloudflare proxy and optionally sets a user domain.
void SetCfProxyConfig(int32_t enabled, int32_t priority, const char *userDomain);

/// Sets the proxy secret (32 hex chars).
void SetSecret(const char *secret);

/// Returns a stats summary string (must be freed with FreeString).
char *GetStats(void);

/// Returns machine-parseable stats "active,bytesUp,bytesDown,wsConnections"
/// (must be freed with FreeString).
char *GetRawStats(void);

/// Returns the secret prefixed with "dd" (must be freed with FreeString).
char *GetSecretWithPrefix(void);

/// Returns the newline-joined list of cfproxy domains (must be freed with FreeString).
char *GetCfProxyDomains(void);

/// Triggers a refresh of cfproxy domains. Returns 1 on success, 0 on failure.
int32_t RefreshCfProxyDomains(void);

/// Frees a string previously returned by the library.
void FreeString(char *ptr);

#ifdef __cplusplus
}
#endif

#endif /* RustBridge_h */