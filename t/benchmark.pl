#!/usr/bin/env perl6

use lib 'lib';

use Bench;
use GeoIP2;

my $geo = GeoIP2.new( path => './t/databases/GeoIP2-City-Test.mmdb' );

Bench.new.timethese(
    1,
    {
        'IPv4' => sub { my %result := $geo.locate( ip => '81.2.69.160' ) }
    }
);

use NativeCall;
use experimental :pack;

my $buf = Buf.new( 0x5a, 0x5d, 0x2a, 0xc4 );
my $expected = 1516055236;

Bench.new.timethese(
    100000,
    {

        'byteshift+byteor' => sub {
            my $out = 0;
    
            for $buf.list -> $byte {
                $out +<= 8;
                $out +|= $byte;
            }
    
            die unless $out == $expected;
        },

        'byteshift+add' => sub {
            my $out = 0;
    
            for $buf.list -> $byte {
                $out +<= 8;
                $out += $byte;
            }
    
            die unless $out == $expected;
        },

        'add_byteshifted' => sub {
            my $out = 0;
    
            for $buf.reverse.kv -> $pos, $byte {
                $out += $byte +< ($pos * 8);
            }
    
            die unless $out == $expected;
        },

        'nativecast' => sub {
            
            my $out = nativecast( Pointer[ uint32 ], $buf.reverse() ).deref( );
    
            die unless $out == $expected;
        },
        
        'nativecast2' => sub {
            
            my $out = nativecast((uint32), $buf.reverse());
    
            die unless $out == $expected;
        },
        
        'unpack' => sub {
            
            my $out = $buf.unpack( 'N' );
    
            die unless $out == $expected;
        }
    }
);