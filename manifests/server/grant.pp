# Define for granting permissions to roles. See README.md for more details.
define postgresql::server::grant (
  $role,
  $db,
  $privilege           = undef,
  $object_type         = 'database',
  $object_name         = $db,
  $psql_db             = $postgresql::server::default_database,
  $psql_user           = $postgresql::server::user,
  $port                = $postgresql::server::port,
  $onlyif_table_exists = false,
) {
  $group     = $postgresql::server::group
  $psql_path = $postgresql::server::psql_path

  ## Munge the input values
  $_object_type = upcase($object_type)
  $_privilege   = upcase($privilege)

  validate_bool($onlyif_table_exists)

  ## Validate that the object type is known
  validate_string($_object_type,
    #'COLUMN',
    'DATABASE',
    #'FOREIGN SERVER',
    #'FOREIGN DATA WRAPPER',
    #'FUNCTION',
    #'PROCEDURAL LANGUAGE',
    #'SCHEMA',
    #'SEQUENCE',
    'TABLE',
    #'TABLESPACE',
    #'VIEW',
  )

  ## Validate that the object type's privilege is acceptable
  # TODO: this is a terrible hack; if they pass "ALL" as the desired privilege,
  #  we need a way to test for it--and has_database_privilege does not
  #  recognize 'ALL' as a valid privilege name. So we probably need to
  #  hard-code a mapping between 'ALL' and the list of actual privileges that
  #  it entails, and loop over them to check them.  That sort of thing will
  #  probably need to wait until we port this over to ruby, so, for now, we're
  #  just going to assume that if they have "CREATE" privileges on a database,
  #  then they have "ALL".  (I told you that it was terrible!)
  case $_object_type {
    'DATABASE': {
      $unless_privilege = $_privilege ? {
        'ALL'   => 'CREATE',
        default => $_privilege,
      }
      validate_string($unless_privilege,'CREATE','CONNECT','TEMPORARY','TEMP',
        'ALL','ALL PRIVILEGES')
      $unless_function = 'has_database_privilege'
      $on_db = $psql_db
      $onlyif_query = undef
    }
    'TABLE': {
      $unless_privilege = $_privilege ? {
        'ALL'   => 'INSERT',
        default => $_privilege,
      }
      validate_string($unless_privilege,'SELECT','INSERT','UPDATE','DELETE',
        'TRUNCATE','REFERENCES','TRIGGER','ALL','ALL PRIVILEGES')
      $unless_function = 'has_table_privilege'
      $on_db = $db
      if $onlyif_table_exists {
        $onlyif_query = "SELECT true FROM pg_tables WHERE tablename = '${object_name}'"
      } else {
        $onlyif_query = undef
      }
    }
    default: {
      fail("Missing privilege validation for object type ${_object_type}")
    }
  }

  $grant_cmd = "GRANT ${_privilege} ON ${_object_type} \"${object_name}\" TO \"${role}\""
  postgresql_psql { $grant_cmd:
    db         => $on_db,
    port       => $port,
    psql_user  => $psql_user,
    psql_group => $group,
    psql_path  => $psql_path,
    onlyif     => $onlyif_query,
    unless     => "SELECT 1 WHERE ${unless_function}('${role}', '${object_name}', '${unless_privilege}')",
    require    => Class['postgresql::server']
  }

  if($role != undef and defined(Postgresql::Server::Role[$role])) {
    Postgresql::Server::Role[$role]->Postgresql_psql[$grant_cmd]
  }

  if($db != undef and defined(Postgresql::Server::Database[$db])) {
    Postgresql::Server::Database[$db]->Postgresql_psql[$grant_cmd]
  }
}
