# Install and Configure Diagrams.Net drawio
#
#   Parameters defined in yaml data file
#   Installs Tomcat and Java
#   Creates DrawIO instance on non-privileged port
#   Creates custom systemd unit file
#   Manages drawio as systemd service
#
#   Expects to work behind an Nginx reverse proxy with SSL offloading and WAF
#
class drawio::install{

  # VARIABLES
  # Data Lookups
  $dw=lookup('drawio::install')             # Hiera data for installation
  $pr=lookup('drawio::provisioning')        # OS-specific variables
  $nx=lookup('nginx::reverse_proxy')        # Reverse proxy variables
  # Tomcat
  $tomcat_base = $dw['tomcat']['base'] # Location of binaries
  $tomcat_version = $dw['tomcat']['version']  # Upgrade tomcat by changing version and url variables
  $tomcat_download_url= $dw['tomcat']['download_url']
  $tomcat_server_port=$dw['tomcat']['server_port']
  $tomcat_temp_dir=$dw['tomcat']['temp_dir']
  # Drawio
  $drawio_version=$dw['drawio']['version']
  $drawio_download_url="${dw['drawio']['download_url_base']}/v${drawio_version}/${dw['drawio']['package_name']}"
  # Tomcat Instance
  $instance_name = $dw['instance']['name']    # Subdirectory name, ex: 'draw'
  $instance_base = $dw['instance']['base']    # Server instance location, ex: '/var/tomcat'
  $instance_max_threads = $dw['instance']['max_threads']   # Thread size 
  $instance_temp_dir="${tomcat_temp_dir}/${instance_name}"
  # systemd unit file
  $systemd_dir=$pr['systemd_dir']
  $service_name="${instance_name}.service"
  $unit_filename = "${systemd_dir}/${service_name}"
  # Nginx Reverse Proxy
  $instance_listen_port = $nx['proxy']['forward_port']

  # Derived Values
  $catalina_home = "${tomcat_base}/${tomcat_version}"  # Tomcat binaries
  $catalina_base = "${instance_base}/${instance_name}"   # Instance directory, example '/var/tomcat/draw'
  $instance_dir = "${catalina_base}/webapps/${dw['instance']['name']}" # '/var/tomcat/draw/webapps/draw'
  $instance_download_dir = "${catalina_base}/download"    # /var/tomcat/draw/download
  $class_path = "${catalina_home}/bin/bootstrap.jar:${catalina_home}/bin/tomcat-juli.jar"

  # Using Tomcat and Java Packages
  class { '::tomcat': }
  class { '::java':   }
  # Prepare Sub Directories
  file{ [
          $tomcat_base,
          $instance_base,
          $tomcat_temp_dir,
          $instance_temp_dir,
        ]:
    ensure => directory,
    owner  => $::tomcat::user,
    group  => $::tomcat::group,
  }
  file {'drawio-download':                              # Directory for downloading drawio war files
    ensure  => directory,
    path    => $instance_download_dir,
    purge   => true,                                    # remove un-used versions
    require => Tomcat::Instance[$instance_name],        # Create file after Tomcat instance is installed
    owner   => $::tomcat::user,
    group   => $::tomcat::group,
  }
  # Install Tomcat
  tomcat::install { $catalina_home:
    source_url => $tomcat_download_url,
  }
  # Drawio is run as an instance
  tomcat::instance { $instance_name:
    catalina_home  => $catalina_home,
    catalina_base  => $catalina_base,
    # Custom systemd unit file is used instead of puppetlabs-tomcat module implementation
    use_jsvc       => false,
    use_init       => false,
    manage_service => false,
  }
  # Service.xml Configuration
  if $tomcat_server_port { # Change management port, if new one specified
    tomcat::config::server { $instance_name:
      catalina_base => $catalina_base,
      port          => $tomcat_server_port,
    }
  }
  # Custom listen port
  if ($instance_listen_port) and ($instance_listen_port != '8080') {
    tomcat::config::server::connector { 'port-8080': # Remove default port if not used
      connector_ensure => 'absent',
      catalina_base    => $catalina_base,
      port             => '8080',
      protocol         => 'HTTP/1.1',
    }
    tomcat::config::server::connector { "${instance_name}-http": # Install new port
      catalina_base         => $catalina_base,
      port                  => $instance_listen_port,
      protocol              => 'HTTP/1.1',
      additional_attributes => {
        'maxThreads'          => $instance_max_threads,
      },
    }
  }
  # Set webapp context to root.  Tomcat will answer http://draw.example.co (not http://example.com/draw)
  tomcat::config::server::context {$instance_name:
    catalina_base         => $catalina_base,
    context_ensure        => 'present',
    parent_service        => 'Catalina',
    parent_engine         => 'Catalina',
    parent_host           => 'localhost',
    additional_attributes => { path=>'' },
    require               => Tomcat::Instance[$instance_name],
  }

  # systemd Service Configuration
  file { $unit_filename: # Custom unit file will manage tomcat instance
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0640',
    content => epp('drawio/tomcat.service.epp',
        {
          'instance_name'     => $instance_name,
          'catalina_home'     => $catalina_home,
          'catalina_base'     => $catalina_base,
          'instance_temp_dir' => $instance_temp_dir,
          'java_home'         => $::java::use_java_home,
          'class_path'        => $class_path
        }
      ),
    notify  => Exec['systemctl daemon-reload'],
  }
  exec {'systemctl daemon-reload':
    refreshonly => true,
    path        =>['/bin'],
    notify      => Service[$service_name],
  }
  service {$service_name:
    ensure     => running,
    enable     => true,
    hasrestart => false,
    hasstatus  => true,
    require    => [
        Tomcat::Config::Server::Context[$instance_name],  # server.xml updates completed
        File[$unit_filename],                             # Unit file is installed
          ],
  }

  # Download and extract drawio

  archive { $instance_name:
    ensure       => present,
    path         => "${instance_download_dir}/${instance_name}-${drawio_version}.war",
    source       => $drawio_download_url,
    extract      => true,
    extract_path => $instance_download_dir, # Target folder path to extract archive
    creates      => "${instance_download_dir}/${drawio_version}",
    cleanup      => true, # remove archive file after extraction
    user         => $::tomcat::user,
    group        => $::tomcat::group,
    require      => File['drawio-download'],
  }

}
