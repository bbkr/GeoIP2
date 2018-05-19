use lib 'lib';

use Test;
use GeoIP2;

plan( 12 );

dies-ok { GeoIP2.new }, 'file path is required';

throws-like { GeoIP2.new( path => './t/databases/nonexistent.mmdb' ) }, X::PathInvalid, 'file path does not exist';

throws-like { GeoIP2.new( path => './t/databases' ) }, X::PathInvalid, 'file path is not directory';

throws-like { GeoIP2.new( path => './t/databases/empty.mmdb' ) }, X::MetaDataNotFound, 'metadata not found';

my $geo;
lives-ok { $geo = GeoIP2.new( path => './t/databases/GeoIP2-City-Test.mmdb' ) }, 'open City database';

my %expected-metadata = (
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
is-deeply $geo.metadata, %expected-metadata, 'metadata with derived fields';

is-deeply $geo.read-node( index => 0 ), ( 1, 1422 ), 'node 0 pointers ( node, node )';
is-deeply $geo.read-node( index => 1024 ), ( 10139, 1431 ), 'node 1024 pointers ( data, missing )';
is-deeply $geo.read-node( index => 1430 ), ( 1431, 1431 ), 'node 1430 pointers ( missing, missing )';
throws-like { $geo.read-node( index => -1 ) }, X::NodeIndexOutOfRange, 'node index cannot be negative';
throws-like { $geo.read-node( index => 1431 ) }, X::NodeIndexOutOfRange, 'node index cannot exceed amount of nodes';

my %expected-location = (
    'city' => {
        'geoname_id' => 2643743,
        'names' => {
            'de' => 'London',
            'en' => 'London',
            'es' => 'Londres',
            'fr' => 'Londres',
            'ja' => 'ロンドン',
            'pt-BR' => 'Londres',
            'ru' => 'Лондон'
        }
    },
    'continent' => {
        'code' => 'EU',
        'geoname_id' => 6255148,
        'names' => {
            'de' => 'Europa',
            'en' => 'Europe',
            'es' => 'Europa',
            'fr' => 'Europe',
            'ja' => 'ヨーロッパ',
            'pt-BR' => 'Europa',
            'ru' => 'Европа',
            'zh-CN' => '欧洲'
        }
    },
    'country' => {
        'geoname_id' => 2635167,
        # test data was generated before brexit
        'is_in_european_union' => True,
        'iso_code' => 'GB',
        'names' => {
            'de' => 'Vereinigtes Königreich',
            'en' => 'United Kingdom',
            'es' => 'Reino Unido',
            'fr' => 'Royaume-Uni',
            'ja' => 'イギリス',
            'pt-BR' => 'Reino Unido',
            'ru' => 'Великобритания',
            'zh-CN' => '英国'
        }
    },
    'location' => {
        'accuracy_radius' => 100,
        # TODO: implement!
        'latitude' => 'NYI!',
        'longitude' => 'NYI!',
        'time_zone' => 'Europe/London'
    },
    'registered_country' => {
        'geoname_id' => 6252001,
        'iso_code' => 'US',
        'names' => {
            'de' => 'USA',
            'en' => 'United States',
            'es' => 'Estados Unidos',
            'fr' => 'États-Unis',
            'ja' => 'アメリカ合衆国',
            'pt-BR' => 'Estados Unidos',
            'ru' => 'США',
            'zh-CN' => '美国'
        }
    },
    'subdivisions' => [
        {
            'geoname_id' => 6269131,
            'iso_code' => 'ENG',
            'names' => {
                'en' => 'England',
                'es' => 'Inglaterra',
                'fr' => 'Angleterre',
                'pt-BR' => 'Inglaterra'
            }
        },
    ]
);
is-deeply $geo.read-location( ip => '81.2.69.160'), %expected-location, 'location found for IPv4';
