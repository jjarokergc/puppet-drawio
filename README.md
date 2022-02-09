# Puppet Module for diagrams.net (drawio)

The development repository is located at: <https://gitlab.jaroker.org>.  A mirror repository is pushed to: <https://github.com/jjarokergc/puppet-drawio> for public access.

## Architecture

This module install the drawio WAR file into a Tomcat instance and creates a systemd unit file for management of the application.  It was developed for Debian-family operating systems.

The module depends on `puppetlabs-java` and `puppetlabs-tomcat` modules but implements its own systemd-based management of the tomcat instance which bypasses the Tomcat scripts (e.g. catalina.sh) in favor of directly running Tomcat in Java.

SSL offloading, caching and security (such as ModSecurity firewall) is provided by an Nginx reverse proxy (which is not part of this module).  This module implements only the proxied server.

The puppet module uses hiera for data lookup, which specifies source location (and version) for downloading, database configuration, nginx configuration and php setup.

 Tested Configuration

* DrawIO 16.5.3
* Tomcat 10.0.16
* Java openjdk 11.0.13

## Main Requirements

Puppetfile.r10k

``` puppet
mod 'puppetlabs-tomcat', '6.1.0'
mod 'puppetlabs-java', '7.3.0'
```

## Usage Example

Server is assigned a profile in `site/role/oss/draw_server.pp`

``` puppet
# Drawio Server
#
class role::oss::draw_server{
  include profile::base_configuration       # Setup server with user accounts, etc.

  # Diagrams.Net drawio utility
  include drawio::install                   # Install drawio instance running Tomcat
  
  # Reverse Proxy Web Access via SSL
  include profile::nginx::reverse_proxy_export # Not part of this module.  Creates nginx reverse proxy.

}
}
```

## Hiera Data Example

data/common.yaml

``` yaml
# draw.example.com
# Module-level defaults
---
# Data Merging Options
# (Over-ride these defaults by using an environment-specific data file)
lookup_options:
  drawio::install:
    merge: hash

drawio::install:
  tomcat: 
    base: '/opt/tomcat' # Location of binaries
    version: '10.0.16'  # Upgrade tomcat by changing version and url variables
    download_url: 'https://dlcdn.apache.org/tomcat/tomcat-10/v10.0.16/bin/apache-tomcat-10.0.16.tar.gz'
    server_port: '8100'
    temp_dir: '/tmp/tomcat'
  drawio:
    download_url: "https://github.com/jgraph/drawio/releases/download/v16.5.3/draw.war"
  instance:
    name: 'draw'        # Subdirectory name
    base: '/var/tomcat' # Server instance location
    max_threads: '400'  # Thread size 
```

## Reverse Proxy

The following is an nginx reference configuration for the reverse proxy (which is not part of this module).

/etc/nginx/sites-enabled/revproxy.draw.example.org.conf

```apacheconf
# MANAGED BY PUPPET
server {
  listen *:80;


  server_name           draw.example.org;
  client_max_body_size 1;


  access_log            /var/log/nginx/revproxy.draw.example.org.access.log;
  error_log             /var/log/nginx/revproxy.draw.example.org.error.log;

  location / {
    return 301 https://$host$request_uri;
  }

  location ~ /\.(?!well-known).* {
    deny all;
    log_not_found on;
    return 404;
  }

  location ^~ /.well-known/acme-challenge/ {
    root      /var/lib/letsencrypt/webroot/;
  }
}
# MANAGED BY PUPPET
server {
  listen       *:443 ssl http2;


  server_name  draw.example.org;

  ssl_certificate           /etc/letsencrypt/live/draw.example.org/fullchain.pem;
  ssl_certificate_key       /etc/letsencrypt/live/draw.example.org/privkey.pem;

  client_max_body_size 1;
  index  index.html index.htm index.php;
  access_log            /var/log/nginx/ssl-revproxy.draw.example.org.access.log;
  error_log             /var/log/nginx/ssl-revproxy.draw.example.org.error.log;


  location ~ /\. {
    limit_req zone=exploit_zone;
    deny all;
    log_not_found on;
    return 404;
  }

  location / {
    modsecurity on;
    modsecurity_rules_file /etc/nginx/modsec/main.conf;
    proxy_pass            http://10.10.10.99:8000;
    proxy_read_timeout    300;
    proxy_connect_timeout 300;
    proxy_send_timeout    90s;
    proxy_redirect        off;
    proxy_http_version    1.1;
    proxy_buffering       off;
    proxy_set_header      Host $host;
    proxy_set_header      X-Real-IP $remote_addr;
    proxy_set_header      X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header      X-Forwarded-Proto $scheme;
    proxy_set_header      Proxy "";
    proxy_cache           cache_0;
  }
}

```

## Author

Jon Jaroker
devops@jaroker.com
