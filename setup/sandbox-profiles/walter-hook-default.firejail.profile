# Walter-OS hook sandbox profile.
# Read-only Walter roots, no network, sensitive homes hidden.
quiet
nonewprivs
noroot
net none
caps.drop all
private-tmp
read-only /
whitelist @WALTER_OS_HOME@
whitelist @WALTER_CONFIG@
read-only @WALTER_OS_HOME@
read-only @WALTER_CONFIG@
blacklist @HOME@/.ssh
blacklist @HOME@/.aws
blacklist @HOME@/.gnupg
blacklist @HOME@/*.pem
blacklist @HOME@/*.key
blacklist @HOME@/*/*.pem
blacklist @HOME@/*/*.key
blacklist @HOME@/*/*/*.pem
blacklist @HOME@/*/*/*.key
blacklist @HOME@/*/*/*/*.pem
blacklist @HOME@/*/*/*/*.key
