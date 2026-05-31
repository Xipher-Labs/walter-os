# Walter-OS skill sandbox profile.
# Workspace scope is writable; operator config is read-only; sensitive homes hidden.
quiet
nonewprivs
noroot
caps.drop all
private-tmp
net none
read-only /
whitelist @WALTER_SANDBOX_PARENT@
whitelist @WALTER_CONFIG@
read-write @WALTER_SANDBOX_PARENT@
read-only @WALTER_CONFIG@
@WALTER_FIREJAIL_CONFIG_KEY_BLACKLISTS@
@WALTER_FIREJAIL_HOME_KEY_BLACKLISTS@
@WALTER_FIREJAIL_SENSITIVE_KEY_BLACKLISTS@
@WALTER_FIREJAIL_INVISIBLE_BLACKLISTS@
blacklist @HOME@/.ssh
blacklist @HOME@/.aws
blacklist @HOME@/.gnupg
blacklist @WALTER_CONFIG@/state/session-*.key
blacklist @WALTER_CONFIG@/state/session-*.key.tmp
