use lib 'lib';

use Test;
use GeoIP2;

plan( 11 );

dies-ok { GeoIP2.new }, 'file path is required';

throws-like { GeoIP2.new( path => './t/databases/nonexistent.mmdb' ) }, X::PathInvalid, 'file path does not exist';

throws-like { GeoIP2.new( path => './t/databases' ) }, X::PathInvalid, 'file path is not directory';

throws-like { GeoIP2.new( path => './t/databases/empty.mmdb' ) }, X::MetaDataNotFound, 'metadata not found';

my $geo;
lives-ok { $geo = GeoIP2.new( path => './t/databases/GeoIP2-City-Test.mmdb' ) }, 'open City database';

my %expected_metadata = (
    'binary_format_major_version' => 2,
    'binary_format_minor_version' => 0,
    'build_epoch' => 1516055236,
    'database_type' => 'GeoIP2-City',
    'description' => {
        'en' => 'GeoIP2 City Test Database (fake GeoIP2 data, for example purposes only)',
        'zh' => '小型数据库'
    },
    'ip_version' => 6,
    'ipv4_start_node' => 96,
    'languages' => [ 'en', 'zh' ],
    'node_byte_size' => 7,
    'node_count' => 1431,
    'record_size' => 28,
    'search_tree_size' => 10017
);
is-deeply $geo.metadata, %expected_metadata, 'metadata';

is-deeply $geo.read-node( index => 0 ), ( 1, 1422 ), 'node 0 pointers ( node, node )';
is-deeply $geo.read-node( index => 1024 ), ( 10139, 1431 ), 'node 1024 pointers ( data, missing )';
is-deeply $geo.read-node( index => 1430 ), ( 1431, 1431 ), 'node 1430 pointers ( missing, missing )';
throws-like { $geo.read-node( index => -1 ) }, X::NodeIndexOutOfRange, 'node index cannot be negative';
throws-like { $geo.read-node( index => 1431 ) }, X::NodeIndexOutOfRange, 'node index cannot exceed amount of nodes';
