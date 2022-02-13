# Drawio Configuration
# 
#  Creates pre- and post-configuration files
#  Integrates with optional services enabled in yaml data file
#
class drawio::config {

  # VARIABLES
  # Data Lookups
  $dw=lookup('drawio::install')             # Hiera data for installation
  $cf=lookup('drawio::configure')           # Gitlab Configuration Parameters
  $nx=lookup('nginx::reverse_proxy')        # Reverse proxy variables

  # Tomcat Instance
  $instance_name = $dw['instance']['name']  # Subdirectory name, 'draw'
  $instance_base = $dw['instance']['base']  # Server instance location, '/var/tomcat'
  $catalina_base = "${instance_base}/${instance_name}"   # Instance for DrawIO application, '/var/tomcat/draw'
  $instance_dir = "${catalina_base}/webapps/${dw['instance']['name']}"
  $service_name="${instance_name}.service"

  # Configuration Parameters
  $drawio_preconfig_file = "${instance_dir}/js/PreConfig.js"
  $drawio_postconfig_file = "${instance_dir}/js/PostConfig.js"
  $drawio_base_url = "https://${nx['server']['name']}"  # Example https://draw.example.com
  $drawio_viewer_url = $cf['viewer']['url'] ? {  # Default to drawio base url if viewer url is empty
                            ''      => "${drawio_base_url}/${cf['viewer']['path']}",
                            default => $cf['viewer']['url'],
                            }
  $drawio_lightbox_url = $cf['lightbox']['url'] ? {  # Default to drawio base url if viewer url is empty
                            ''      => "${drawio_base_url}/${cf['lightbox']['path']}",
                            default => $cf['lightbox']['url'],
                            }
  $web_inf_dir = "${instance_dir}/WEB-INF"
  $aws_iot_dir = "${web_inf_dir}/aws_iot_auth"


  # Configuration Files
  file {$drawio_preconfig_file:
    ensure  => file,
    owner   => $::tomcat::user,
    group   => $::tomcat::group,
    mode    => '0644',
    content => epp('drawio/drawio_preconfig.epp',
        {
          'cf'                  => $cf,                 # Hash of config (cf) parameters
          'drawio_base_url'     => $drawio_base_url,    # Example https://draw.example.com
          'drawio_viewer_url'   => $drawio_viewer_url,  # Example https://draw.example.com/js/viewer.min.js
          'drawio_lightbox_url' => $drawio_lightbox_url,# Example https://draw.example.com/js/viewer.min.js
        }
      ),
    notify  => Service[$service_name],
    require => File[$instance_name],        # Create file after WAR downloaded
  }
  file {$drawio_postconfig_file:
    ensure  => file,
    owner   => $::tomcat::user,
    group   => $::tomcat::group,
    mode    => '0644',
    content => epp('drawio/drawio_postconfig.epp',
        {
          'cf'                  => $cf,                 # Hash of config (cf) parameters
        }
      ),
    notify  => Service[$service_name],
    require => File[$instance_name],        # Create file after WAR downloaded
  }

  # Drawio IOT Endpoint Configuration
  if $cf['iot']['endpoint'] != '' { # If endpoint is defined

    file { $aws_iot_dir:
      ensure  => directory,
      owner   => $::tomcat::user,
      group   => $::tomcat::group,
      require => File[$instance_name],        # Create file after WAR downloaded
    }
    file { "${aws_iot_dir}/mxPusherSrv.cert.pem":
      content => $cf['iot']['cert_pem'],
      owner   => $::tomcat::user,
      group   => $::tomcat::group,
    }
    file { "${aws_iot_dir}/mxPusherSrv.private.key":
      content => $cf['iot']['private_key'],
      owner   => $::tomcat::user,
      group   => $::tomcat::group,
    }
    file { "${aws_iot_dir}/root-CA.crt":
      content => $cf['iot']['root_ca'],
      owner   => $::tomcat::user,
      group   => $::tomcat::group,
    }
    file { "${aws_iot_dir}/endpoint_url":
      content => $cf['iot']['endpoint'],
      owner   => $::tomcat::user,
      group   => $::tomcat::group,
    }
  }
  # Google Integration
  if $cf['google']['client_id'] != '' {

    $content_id = $cf['google']['viewer']['client_id'] ? {
      ''      => "/:::/${cf['google']['client_id']}\n/:::/${cf['google']['viewer']['client_id']}",
      default => "/:::/${cf['google']['viewer']['client_id']}",
    }

    $content_secret= $cf['google']['viewer']['client_id'] ? {
      ''      => "/:::/${cf['google']['client_secret']}\n/:::/${cf['google']['viewer']['client_secret']}",
      default => "/:::/${cf['google']['viewer']['client_secret']}",
    }

    file { "${web_inf_dir}/google_client_id":
      content => $content_id,
      owner   => $::tomcat::user,
      group   => $::tomcat::group,
      require => File[$instance_name],        # Create file after WAR downloaded
    }
    file { "${web_inf_dir}/google_client_secret":
      content => $content_secret,
      owner   => $::tomcat::user,
      group   => $::tomcat::group,
      require => File[$instance_name],        # Create file after WAR downloaded
    }
  }

  #MS Graph Integration
  if $cf['msgraph']['client_id'] != '' {

    file { "${web_inf_dir}/msgraph_client_id":
      content => $cf['msgraph']['client_id'],
      owner   => $::tomcat::user,
      group   => $::tomcat::group,
      require => File[$instance_name],        # Create file after WAR downloaded
    }
    file { "${web_inf_dir}/msgraph_client_secret":
      content => $cf['msgraph']['client_secret'],
      owner   => $::tomcat::user,
      group   => $::tomcat::group,
      require => File[$instance_name],        # Create file after WAR downloaded
    }
  }

  # Gitlab (Gitlab server flow auth (since 14.6.7) Integration
  if $cf['gitlab']['id'] != '' {

    file { "${web_inf_dir}/gitlab_auth_url":
      content => $cf['gitlab']['url'],
      owner   => $::tomcat::user,
      group   => $::tomcat::group,
      require => File[$instance_name],        # Create file after WAR downloaded
    }
    file { "${web_inf_dir}/gitlab_client_id":
      content => $cf['gitlab']['id'],
      owner   => $::tomcat::user,
      group   => $::tomcat::group,
      require => File[$instance_name],        # Create file after WAR downloaded
    }
    file { "${web_inf_dir}/gitlab_client_secret":
      content => $cf['gitlab']['secret'],
      owner   => $::tomcat::user,
      group   => $::tomcat::group,
      require => File[$instance_name],        # Create file after WAR downloaded
    }
  }

  # Cloud Key Integration
  if $cf['cloud_convert_apikey'] != '' {
    file { "${web_inf_dir}/cloud_convert_api_key":
      content => $cf['cloud_convert_apikey'],
      owner   => $::tomcat::user,
      group   => $::tomcat::group,
      require => File[$instance_name],        # Create file after WAR downloaded
    }
  }

}


