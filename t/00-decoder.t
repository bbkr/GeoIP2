use lib 'lib';

use Test;
use GeoIP2;

plan( 1 );

dies-ok { GeoIP2.new }, 'file path is required';

throws-like { GeoIP2.new( path => './t/databases/nonexistent.mmdb' ) }, X::DatabasePathInvalid, 'file path does not exist';

throws-like { GeoIP2.new( path => './t/databases' ) }, X::DatabasePathInvalid, 'file path is not directory';

throws-like { GeoIP2.new( path => './t/databases/empty.mmdb' ) }, X::DatabaseMetaDataNotFound, 'metadata not found';

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
    'languages' => [ 'en', 'zh' ],
    'node_count' => 1431,
    'record_size' => 28
);
is-deeply $geo.metadata, %expected_metadata, 'metadata';
