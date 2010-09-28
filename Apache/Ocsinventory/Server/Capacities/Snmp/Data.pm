###############################################################################
## OCSINVENTORY-NG 
## Copyleft Pascal DANEK 2008
## Web : http://www.ocsinventory-ng.org
##
## This code is open source and may be copied and modified as long as the source
## code is always made freely available.
## Please refer to the General Public Licence http://www.gnu.org/ or Licence.txt
################################################################################
package Apache::Ocsinventory::Server::Capacities::Snmp::Data;

use strict;

require Exporter;

our @ISA = qw /Exporter/;

our @EXPORT = qw / 
  _init_snmp_map 
  _get_snmp_bind_values 
  _get_snmp_parser_ForceArray 
/;

use Apache::Ocsinventory::Map;
use Apache::Ocsinventory::Server::System qw / :server /;

#TODO: see if we can use a comman Data.pm for standard inventory and snmp inventory. Maybe a var for HARDWARE_ID and SNMp_ID and a common grep to select tables ?
sub _init_snmp_map{
  my ($sectionsMeta, $sectionsList) = @_;
  my $section;
  my @bind_num;
  my $field;
  my $fields_string;
  my $field_index;
  
  # Parse snmp sections only
  for $section (keys(%DATA_MAP)){
    if ($DATA_MAP{$section}->{capacities} =~ /^snmp$/ ) {
    $field_index = 0;
    # Field array (from data_map field hash keys), filtered fields and cached fields
    $sectionsMeta->{$section}->{field_arrayref} = [];
    $sectionsMeta->{$section}->{field_filtered} = [];
    $sectionsMeta->{$section}->{field_cached} = {};
    ##############################################
    # Don't process the non-auto-generated sections
    next if !$DATA_MAP{$section}->{auto};
    $sectionsMeta->{$section}->{multi} = 1 if $DATA_MAP{$section}->{multi};
    $sectionsMeta->{$section}->{delOnReplace} = 1 if $DATA_MAP{$section}->{delOnReplace};
    $sectionsMeta->{$section}->{writeDiff} = 1 if $DATA_MAP{$section}->{writeDiff};
    $sectionsMeta->{$section}->{cache} = 1 if $DATA_MAP{$section}->{cache};
    $sectionsMeta->{$section}->{name} = $section;
    # $sectionsMeta->{$section}->{hasChanged} is set while inventory update
     
    # Parse fields of the current section
    for $field ( keys(%{$DATA_MAP{$section}->{fields}} ) ){
      if(!$DATA_MAP{$section}->{fields}->{$field}->{noSql}){
        push @{$sectionsMeta->{$section}->{field_arrayref}}, $field;
        $sectionsMeta->{$section}->{noSql} = 1 unless $sectionsMeta->{$section}->{noSql};
      }
      if($DATA_MAP{$section}->{fields}->{$field}->{filter}){
        next unless $ENV{OCS_OPT_INVENTORY_FILTER_ENABLED};
        push @{$sectionsMeta->{$section}->{field_filtered}}, $field;
        $sectionsMeta->{$section}->{filter} = 1 unless $sectionsMeta->{$section}->{filter};
      }
      if($DATA_MAP{$section}->{fields}->{$field}->{cache}){
        next unless $ENV{OCS_OPT_INVENTORY_CACHE_ENABLED};
        $sectionsMeta->{$section}->{field_cached}->{$field} = $field_index;
        $sectionsMeta->{$section}->{cache} = 1 unless $sectionsMeta->{$section}->{cache};
      }
      if(defined $DATA_MAP{$section}->{fields}->{$field}->{fallback}){
        $sectionsMeta->{$section}->{fields}->{$field}->{fallback} = $DATA_MAP{$section}->{fields}->{$field}->{fallback};
      }
      
      if(defined $DATA_MAP{$section}->{fields}->{$field}->{type}){
        $sectionsMeta->{$section}->{fields}->{$field}->{type} = $DATA_MAP{$section}->{fields}->{$field}->{type};
      }
      $field_index++;      
    }
    # Build the "DBI->prepare" sql insert string 
    $fields_string = join ',', ('SNMP_ID', @{$sectionsMeta->{$section}->{field_arrayref}});
    $sectionsMeta->{$section}->{sql_insert_string} = "INSERT INTO $section($fields_string) VALUES(";
    for(0..@{$sectionsMeta->{$section}->{field_arrayref}}){
      push @bind_num, '?';
    }
    
    $sectionsMeta->{$section}->{sql_insert_string}.= (join ',', @bind_num).')';
    @bind_num = ();
    # Build the "DBI->prepare" sql select string 
    $sectionsMeta->{$section}->{sql_select_string} = "SELECT ID,$fields_string FROM $section 
      WHERE SNMP_ID=? ORDER BY ".$DATA_MAP{$section}->{sortBy};
    # Build the "DBI->prepare" sql deletion string 
    $sectionsMeta->{$section}->{sql_delete_string} = "DELETE FROM $section WHERE SNMP_ID=? AND ID=?";
    # to avoid many "keys"
    push @$sectionsList, $section;
  }
  }
}

sub _get_snmp_bind_values{
  my ($refXml, $sectionMeta, $arrayToFeed) = @_;

  my $bind_value;

  for my $field ( @{ $sectionMeta->{field_arrayref} } ) {
    if(defined($refXml->{$field}) && $refXml->{$field} ne '' && $refXml->{$field} ne '??' && $refXml->{$field}!~/^N\/?A$/){
      $bind_value = $refXml->{$field}
    }
    else{
       if( defined $sectionMeta->{fields}->{$field}->{fallback} ){
         $bind_value = $sectionMeta->{fields}->{$field}->{fallback};
         &_log( 000, 'fallback', "$field:".$sectionMeta->{fields}->{$field}->{fallback}) if $ENV{'OCS_OPT_LOGLEVEL'}>1;
       }
       else{
         &_log( 000, 'generic-fallback', "$field:".$sectionMeta->{fields}->{$field}->{fallback}) if $ENV{'OCS_OPT_LOGLEVEL'}>1;
         $bind_value = '';
       }
    }
    # We have to substitute the value with the ID matching "type_section_field.name" if the field is tagged "type".
    # It allows to support different DB structures
    if( defined $sectionMeta->{fields}->{$field}->{type} ){
      $bind_value = _get_type_id($sectionMeta->{name}, $field, $bind_value);
    }

    if($ENV{'OCS_OPT_UNICODE_SUPPORT'}) {
      my $utf8 = $bind_value;
      utf8::decode($utf8);
      push @$arrayToFeed, $utf8;
    }
    else {
      push @$arrayToFeed, $bind_value;
    }
  }
}

sub _get_snmp_parser_ForceArray{
  my $arrayRef = shift ;

  for my $section (keys(%DATA_MAP)){
    if ($DATA_MAP{$section}->{capacities} =~ /^snmp$/ ) {
    # Feed the multilines section array in order to parse xml correctly
      if ($DATA_MAP{$section}->{multi}) {
        #We delete the snmp_ pattern to be in concordance with XML
        $section =~ s/snmp_//g;    
        push @$arrayRef, uc $section;
      }
    }
  }
}

1;



