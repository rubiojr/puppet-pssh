# puppet-pssh 

Puppet parallel-ssh integration.

Needs parallel-ssh installed (apt-get install pssh on Ubuntu/Debian).

# Install

    gem install puppet-pssh

# Usage

The command has a built-in help:

    puppet-pssh --help

The run command:

    puppet-pssh run --puppetmaster 192.168.1.1 \ 
                    --match 'openstack|swift|compute' \
                    --nameserver 10.0.0.1 \
                    --no-host-key-verify \
                    puppet agent -t

This will run the command 'puppet agent -t' on every node whose FQDN matches /openstack|swift|compute/ (regexp). It will try to resolve node names using DNS server 10.0.0.1 and use the IP address instead.
Also, SSH host key verification also is disabled.
    

# Copyright

Copyright (c) 2012 Sergio Rubio. See LICENSE.txt for
further details.

