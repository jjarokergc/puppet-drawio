# Install and Configure Diagrams.Net drawio
#
class drawio::install{

  # VARIABLES
  $tomcat_base = '/opt/tomcat' # Location of binaries
  $tomcat_version = '10.0.16'  # Upgrade tomcat by changing version and url variables
  $tomcat_download_url='https://dlcdn.apache.org/tomcat/tomcat-10/v10.0.16/bin/apache-tomcat-10.0.16.tar.gz'

  $drawio_version = 'v16.5.3'
  $drawio_download_url="https://github.com/jgraph/drawio/releases/download/${drawio_version}/draw.war"

  $instance_name = 'draw'       # Subdirectory name
  $instance_base = '/var/tomcat'  # Server instance location
  $instance_max_threads = '400'   # Thread size 

  $catalina_home = "${tomcat_base}/${tomcat_version}"  # Tomcat binaries
  $catalina_base = "${instance_base}/${instance_name}"   # Instance
  $class_path = "${catalina_home}/bin/bootstrap.jar:${catalina_home}/bin/tomcat-juli.jar"

  $tomcat_temp_dir='/tmp/tomcat'

  $systemd_dir='/etc/systemd/system'
  $service_name="${instance_name}.service"
  $unit_filename = "${systemd_dir}/${service_name}"

  # Nginx Reverse Proxy
  $nx_proxy = lookup('nginx::reverse_proxy')
  $instance_listen_port = $nx_proxy['proxy']['forward_port']


  class { '::tomcat': }
  class { '::java':   }

  file{ [
          $tomcat_base,
          $instance_base,
          $tomcat_temp_dir,
        ]:
    ensure => directory,
    owner  => 'tomcat',
    group  => 'tomcat',
  }

  tomcat::install { $catalina_home:
    source_url => $tomcat_download_url,
  }

  tomcat::instance { $instance_name:
    catalina_home  => $catalina_home,
    catalina_base  => $catalina_base,
    use_jsvc       => false,
    use_init       => false,
    manage_service => false,
  }

  # Service.xml Configuration
  # Change the default port of the second instance server and HTTP connector
  tomcat::config::server { $instance_name:
    catalina_base => $catalina_base,
    port          => '8100',
  }
  tomcat::config::server::connector { "${instance_name}-http":
    catalina_base         => $catalina_base,
    port                  => $instance_listen_port,
    protocol              => 'HTTP/1.1',
    additional_attributes => {
      'maxThreads'          => $instance_max_threads,
    },
  }
  # Remove default port
  tomcat::config::server::connector { 'port-8080':
    connector_ensure => 'absent',
    catalina_base    => $catalina_base,
    port             => '8080',
    protocol         => 'HTTP/1.1',
  }
  # Set webapp context to root
  tomcat::config::server::context {$instance_name:
    catalina_base         => $catalina_base,
    context_ensure        => 'present',
    parent_service        => 'Catalina',
    parent_engine         => 'Catalina',
    parent_host           => 'localhost',
    additional_attributes => {
                      path=>''  #Tomcat warning: either empty or start with '/' and not end with '/'
                      },
    require               => Tomcat::Instance[$instance_name],
  }

  # systemd Service Configuration
  file { $unit_filename: # Custom unit file will manage tomcat instance
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0777',
    content => epp('drawio/tomcat.service.epp',
        {
          'instance_name'   => $instance_name,
          'catalina_home'   => $catalina_home,
          'catalina_base'   => $catalina_base,
          'tomcat_temp_dir' => $tomcat_temp_dir,
          'java_home'       => $::java::use_java_home,
          'class_path'      => $class_path
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


  # Install Drawio Package
  tomcat::war { "${instance_name}.war":
    catalina_base => $catalina_base,
    war_source    => $drawio_download_url,
  }

}
