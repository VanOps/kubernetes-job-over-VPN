#!/bin/bash
set -e

# Generate host keys if they don't exist
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    echo "Generating SSH host keys..."
    ssh-keygen -A
fi

# Setup authorized_keys from mounted secret if available
if [ -f /tmp/authorized_keys ]; then
    echo "Installing authorized_keys from mounted secret..."
    cp /tmp/authorized_keys /home/ansible/.ssh/authorized_keys
    chown ansible:ansible /home/ansible/.ssh/authorized_keys
    chmod 600 /home/ansible/.ssh/authorized_keys
    echo "✓ SSH key installed for user 'ansible'"
elif [ -n "$SSH_PUBLIC_KEY" ]; then
    echo "Installing authorized_keys from environment variable..."
    echo "$SSH_PUBLIC_KEY" > /home/ansible/.ssh/authorized_keys
    chown ansible:ansible /home/ansible/.ssh/authorized_keys
    chmod 600 /home/ansible/.ssh/authorized_keys
    echo "✓ SSH key installed from \$SSH_PUBLIC_KEY"
else
    echo "⚠️  WARNING: No SSH public key provided!"
    echo "   Mount public key at /tmp/authorized_keys or set \$SSH_PUBLIC_KEY"
fi

# Display server info
echo "=========================================="
echo "SSH Test Server (Debian Bookworm)"
echo "=========================================="
echo "User: ansible"
echo "Authentication: Public key only"
echo "Root login: Disabled"
echo "Password auth: Disabled"
echo "=========================================="

# Execute CMD
exec "$@"
