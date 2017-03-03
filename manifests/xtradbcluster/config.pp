define mysql::xtradbcluster::config(
                                      $serverid,
                                      $wsrep_node_address = $::ipaddress,
                                      $instance_name      = $name,
                                      $cluster_name       = $name,
                                      $port               = '3306',
                                      $add_default_mycnf  = false,
                                      $instancedir        = "/var/mysql/${name}",
                                      $datadir            = "/var/mysql/${name}/datadir",
                                      $relaylogdir        = "/var/mysql/${name}/binlogs",
                                      $logdir             = "/var/log/mysql/${name}",
                                    ) {

  if($add_default_mycnf)
  {
    mysql::mycnf { $instance_name:
      require => Class['::mysql'],
    }

    mysql::mycnf::mysqld{ $instance_name:
      port                     => $port,
      datadir                  => $datadir,
      relaylogdir              => $relaylogdir,
      log_error                => "${logdir}/mysql-error.log",
      slow_query_log_file      => "${logdir}/mysql-slow.log",
      binlog_format            => 'ROW',
      default_storage_engine   => 'InnoDB',
      innodb_autoinc_lock_mode => '2',
      serverid                 => $serverid,
    }

    mysql::mycnf::galera { $instance_name:
      wsrep_cluster_name => $cluster_name,
      wsrep_node_address => $::ipaddress,
    }
  }
}
