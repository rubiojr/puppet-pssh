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
                    --match 'openstack-compute' \
                    --nameserver 10.0.0.1 \
                    --no-host-key-verify \
                    --threads 20 \                # use up to 20 threads
                    puppet agent -t

This will run the command 'puppet agent -t' on every node whose FQDN matches /openstack-compute/ (regexp). It will try to resolve node names using DNS server 10.0.0.1 and use the IP address instead.
Also, SSH host key verification has been disabled.
    
# Tips

Clean node's /var/lib/puppet and revoke node cert on master also:

    # Clean /var/lib/puppet in node
    puppet-pssh run 'find /var/lib/puppet -type f|xargs rm'
    # Revoke cert (this will run in the node!)
    puppet-pssh run 'curl -k -X PUT -H "Content-Type: text/pson" --data '\''{"desired_state":"revoked"}'\'' https://puppetmaster.devel.bvox.net:8140/development/certificate_status/`hostname -f`'
    puppet-pssh run 'curl -k -X DELETE -H "Accept: pson" https://puppetmaster.devel.bvox.net:8140/development/certificate_status/`hostname -f`'

Your puppet master's auth.conf some rules for this to work. See:

http://www.mail-archive.com/puppet-users@googlegroups.com/msg35412.html

# Copyright

Copyright (c) 2012 Sergio Rubio. See LICENSE.txt for
further details.

