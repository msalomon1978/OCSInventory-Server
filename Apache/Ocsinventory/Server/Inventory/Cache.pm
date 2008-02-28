###############################################################################
## OCSINVENTORY-NG 
## Copyleft Pascal DANEK 2008
## Web : http://www.ocsinventory-ng.org
##
## This code is open source and may be copied and modified as long as the source
## code is always made freely available.
## Please refer to the General Public Licence http://www.gnu.org/ or Licence.txt
################################################################################
package Apache::Ocsinventory::Server::Inventory::Cache;

use strict;

require Exporter;

our @ISA = qw /Exporter/;

our @EXPORT = qw / 
  _reset_inventory_cache 
  _add_cache
/;

use Apache::Ocsinventory::Map;
use Apache::Ocsinventory::Server::System qw / :server /;

sub _add_cache{
  my ($section, $sectionMeta, $values ) = @_;
  
  my $dbh = $Apache::Ocsinventory::CURRENT_CONTEXT{'DBI_HANDLE'};
  my @fields_array = keys %{ $sectionMeta->{field_cached} };
  
  for my $field ( @fields_array ){
    my $table = $section.'_'.lc $field.'_cache';
    if( $dbh->do("SELECT $field FROM $table WHERE $field=?", {}, $values->[ $sectionMeta->{field_cached}->{$field} ]) == 0E0){
      $dbh->do("INSERT INTO $table($field) VALUES(?)", {}, $values->[ $sectionMeta->{field_cached}->{$field} ]);
    }
  }
}

sub _reset_inventory_cache{
  my ( $sectionsMeta, $sectionsList ) = @_;
  
  return if !$ENV{OCS_OPT_INVENTORY_CACHE_REVALIDATE};
  
  my $dbh = $Apache::Ocsinventory::CURRENT_CONTEXT{'DBI_HANDLE'};
  
  if( &_check_cache_validity() ){
    
    &_log(110,'inventory_cache','checking') if $ENV{'OCS_OPT_LOGLEVEL'};
    
    if( &_lock_cache() ){
      for my $section ( @$sectionsList ){
        my @fields_array = keys %{ $sectionsMeta->{$section}->{field_cached} };
        for my $field (@fields_array){
          my $table = $section.'_'.lc $field.'_cache';
          &_log(108,'inventory_cache',"cache($section.$field)") if $ENV{'OCS_OPT_LOGLEVEL'};
          my $src_table = lc $section;
          if( $dbh->do("TRUNCATE TABLE $table") ){
            if( $dbh->do("INSERT INTO $table($field) SELECT DISTINCT $field FROM $src_table") ){
              &_log(109,'inventory_cache',"ok:$section.$field") if $ENV{'OCS_OPT_LOGLEVEL'};
            }
            else{
              &_log(522,'inventory_cache',"fault:$section.$field") if $ENV{'OCS_OPT_LOGLEVEL'};
              &_lock_cache_release();
              return;
            }
          }
          else{
            &_log(523,'inventory_cache',"fault:$section.$field") if $ENV{'OCS_OPT_LOGLEVEL'};
            &_lock_cache_release();
            return;
          }
        }
      }
    }
    else{
      &_log(111,'inventory_cache','already_handled') if $ENV{'OCS_OPT_LOGLEVEL'};
      return;
    }
    $dbh->do('INSERT INTO engine_persistent(NAME,IVALUE) VALUES("INVENTORY_CACHE_CLEAN_DATE", UNIX_TIMESTAMP(NOW()))')
      if($dbh->do('UPDATE engine_persistent SET IVALUE=UNIX_TIMESTAMP(NOW()) WHERE NAME="INVENTORY_CACHE_CLEAN_DATE"')==0E0);
    
    &_lock_cache_release();
    &_log(109,'inventory_cache','done') if $ENV{'OCS_OPT_LOGLEVEL'};
  }
  else{
    return;
  }
}

sub _check_cache_validity{
  my $dbh = $Apache::Ocsinventory::CURRENT_CONTEXT{'DBI_HANDLE'};
  my $check_cache = $dbh->prepare('SELECT UNIX_TIMESTAMP(NOW())-IVALUE AS IVALUE FROM engine_persistent WHERE NAME="INVENTORY_CACHE_CLEAN_DATE"');
  $check_cache->execute();
  if($check_cache->rows()){
    my $row = $check_cache->fetchrow_hashref();
    if($row->{IVALUE}< $ENV{OCS_OPT_INVENTORY_CACHE_REVALIDATE}*86400 ){
      return 0;
    }
    else{
      return 1;
    }
  }
  else{
    return 1;
  }
}

sub _lock_cache{
  return $Apache::Ocsinventory::CURRENT_CONTEXT{'DBI_HANDLE'}->do("INSERT INTO engine_mutex(NAME, PID, TAG) VALUES('INVENTORY_CACHE_REVALIDATE',?,'ALL')", {}, $$)
}

sub _lock_cache_release{
  return $Apache::Ocsinventory::CURRENT_CONTEXT{'DBI_HANDLE'}->do("DELETE FROM engine_mutex WHERE NAME='INVENTORY_CACHE_REVALIDATE' AND PID=?", {}, $$);
}
1;

















