# MaxMind GeoIP v2 libraries reader for [Raku](https://www.raku.org) language

[![.github/workflows/test.yml](https://github.com/bbkr/GeoIP2/actions/workflows/test.yml/badge.svg)](https://github.com/bbkr/GeoIP2/actions/workflows/test.yml)

Reader for [MaxMind databases](https://www.maxmind.com/en/geoip2-databases) including:
* Country
* City
* Anonymous IP
* ISP
* Domain
* Connection Type
* in any distribution form ( Lite, Pro, Enterprise )
* and any other database in [*.mmdb 2.0 format](https://github.com/maxmind/MaxMind-DB/blob/master/MaxMind-DB-spec.md)

## SYNOPSIS

```raku
    use GeoIP2;
    
    my $geo = GeoIP2.new( path => '/home/me/Database.mmdb' );
    
    # lookup by IPv4
    say $geo.locate( ip => '8.8.8.8' );
    
    # lookup by IPv6
    say $geo.locate( ip => '2001:4860:4860:0:0:0:0:8888' );
    
    # show database information
    say $geo.build-timestamp;
    say $geo.ip-version;
    say $geo.languages;
    say $geo.description;
```

## METHODS

### new( path => '/home/me/Database.mmdb' )

Initialize database.

### locate( ip => '1.1.1.1' )

Return location data for given IP or `Nil` if IP is not found.

IP can be given as:
* IPv4 dotted decimal format - `8.8.8.8`
* IPv6 full format - `2001:4860:4860:0000:0000:0000:0000:8888`
* IPv6 without leading zeroes - `2001:4860:4860:0:0:0:0:8888`
* (IPv6 compressed format - `2001:4860:4860::8888` - is not yet supported)

Note that returned data structure is specific for opened databse type,
for example ISP database returns:

```raku
GeoIP2.new( path => './GeoIP2-ISP.mmdb' ).locate( ip => '78.31.153.58' );

{
    'autonomous_system_number' => 29314,
    'autonomous_system_organization' => 'Vectra S.A.',
    'isp' => 'Jarsat Sp. z o.o.',
    'organization' => 'Jarsat Sp. z o.o.'
}
```

Sometimes returned values are localized, like in City database:

```raku
GeoIP2.new( path => './GeoIP2-City.mmdb' ).locate( ip => '78.31.153.58' );

{
    'country' => {
        'geoname_id' => 798544,
        'names' => {
            'ru' => 'Польша',
            'es' => 'Polonia',
            'pt-BR' => 'Polônia',
            'zh-CN' => '波兰',
            'ja' => 'ポーランド共和国',
            'de' => 'Polen',
            'fr' => 'Pologne',
            'en' => 'Poland'
        },
        'iso_code' => 'PL',
        'is_in_european_union' => True
    },
    'city' => {
        'geoname_id' => 3099434,
        'names' => {
            'ru' => 'Гданьск',
            'es' => 'Gdansk',
            'pt-BR' => 'Gdańsk',
            'zh-CN' => '格但斯克',
            'ja' => 'グダニスク',
            'de' => 'Danzig',
            'fr' => 'Gdańsk',
            'en' => 'Gdańsk'
        }
    },
    'continent' => {
        'geoname_id' => 6255148,
        'names' => {
            'ru' => 'Европа',
            'es' => 'Europa',
            'pt-BR' => 'Europa',
            'zh-CN' => '欧洲',
            'ja' => 'ヨーロッパ',
            'de' => 'Europa',
            'fr' => 'Europe',
            'en' => 'Europe'
        },
    }
    'subdivisions' => [
        {
            'geoname_id' => 3337496,
            'iso_code' => 'PM',
            'names' => {
                'de' => 'Woiwodschaft Pommern',
                'en' => 'Pomerania',
                'es' => 'Pomerania',
                'fr' => 'Voïvodie de Poméranie',
                'ja' => 'ポモージェ県',
                'ru' => 'Поморское воеводство'
            }
        }
    ],
    ...
}
```

In such case list of available languages can be also checked through [languages](#languages) attribute.
If your language is not provided out-of-the-box please check [TRANSLATIONS](#translations) section.

## ATTRIBUTES

### build-timestamp

DateTime object representing time when database was compiled.

### ip-version

Version object representing largest supported IP type, for example `v6`.

### languages

Set object representing languages that location names are translated to.
Check [TRANSLATIONS](#translations) section if language that you need is not on the list.

### description / description( 'RU' )

String describing database kind, for example `GeoIP2 ISP database`.
Default is English but it may be requested in any of the [supported languages](#languages).

### binary-format-version / database-type / ipv4-start-node / node-byte-size / node-count / record-size / search-tree-size

Geeky stuff.

## FLAGS

### debug

Helpful for investigating IP loation and data decoding issues.
Can be passed in constructor or turned `True` / `False` at any time:

```raku
my $geo = GeoIP2.new( path => '/home/me/Database.mmdb', :debug );
...
$geo.debug = False;
...
$geo.debug = True;
...
```

## REQUIREMENTS

This is Pure Raku module - maxminddb C library is **not** required.
Here is how to start with free GeoIP Lite libraries right away:

### MacOS

* Install [HomeBrew](https://brew.sh).

In terminal:

* Install tool to fetch databases - `brew install geoipupdate`.
* Fetch databases - `geoipupdate` (may take a while).

In code:

```raku
my $geo = GeoIP2.new( path => '/usr/local/var/GeoIP/GeoLite2-City.mmdb' );
say $geo.locate( ip => '8.8.8.8' );
```

### Ubuntu Linux and derivatives

In terminal:

* Install tool to fetch databases - `sudo apt-get install geoipupdate`.
* Fetch databases - `sudo geoipupdate` (may take a while).

In code:

```raku
my $geo = GeoIP2.new( path => '/var/lib/GeoIP/GeoLite2-City.mmdb' );
say $geo.locate( ip => '8.8.8.8' );
```

### Arch Linux and derivatives

In terminal:

* Install prepackaged databases - `pacman -Syu geoip2-database`.

In code:

```raku
my $geo = GeoIP2.new( path => '/usr/share/GeoIP/GeoLite2-City.mmdb' );
say $geo.locate( ip => '8.8.8.8' );
```

Note that `geoipupdate` tool method is also possible,
but because Arch is a rolling release distro installing prepackaged databases
provides the same frequency of database updates as fetching direcltly from MaxMind.

## TRANSLATIONS

Some databases have built-in translations, however set of supported languages is rather limited.
Additional translations can be obtained from [GeoNames.org](https://geonames.org) by using `geoname_id` column from results.

The easiest way to do that is to download [this file](http://download.geonames.org/export/dump/alternateNamesV2.zip).
Inside ZIP archive there is tab-separated `alternateNamesV2.txt` file, where:

* second column is `geoname_id`
* third column may contain 2 or 3 letter lowercased ISO-639 language code
* fourth column contains traslation
* fifth column contains 1 if name is official, otherwise it is empty

So if you need for example Hungarian translation for country from example above you can extract it:

```
$ cat alternateNamesV2.txt | awk -F "\t" '{ if ( $2 == 798544 && $3 == "hu" ) print $4 }'
Lengyelország
```

Sometimes there are few translations in the same language:

```
$ cat alternateNamesV2.txt | awk -F "\t" '{ if ( $2 == 798544 && $3 == "en" ) print $4 }'
Poland
Republic of Poland
```

Usually one of them will be marked as "official" (fifth column),
so you can treat such translation with higher priority.

### Native names

Unfortunately there is no indicator which translation is native for which `geoname_id`.
First you have to check which langauge is used in given country and then find translation in that language.

But beware, there are some countries with more than one official language so you may get more than one native name.
It is up to you to decide how to handle such cases.

### Caching ideas

For fast access you may want to preload those translations into some fast database, for example Redis.
Let's say you need Swedish translations (language code is `SV`).

Feed unofficial names first (fifth column empty):
```
cat alternateNamesV2.txt | awk -F "\t" '{ if ( $3 == "sv" && $5 == "" ) print "HSET " $2 " " $3 " \"" $4 "\""}' | redis-cli
```

Then feed known, official names (fifth column is `1`):
```
cat alternateNamesV2.txt | awk -F "\t" '{ if ( $3 == "sv" && $5 == 1 ) print "HSET " $2 " " $3 " \"" $4 "\""}' | redis-cli
```
Sometimes official name will overwrite unofficial name.

And to find translation of `geoname_id` in Swedish language you simply have to query Redis:
```
> HGET 798544 sv
"Polen"
```

You can feed more languages into the same database if you need.

## COPYRIGHTS

This third party reader is released under Artistic-2.0 license
and is based on [open source database spec](https://github.com/maxmind/MaxMind-DB) released under Creative Commons license.
Which means you can use it to read GeoIP2 free and paid databases both for personal and commercial use.

However keep in mind that MaxMind® and GeoIP® [are trademarks](https://www.maxmind.com/en/terms_of_use)
so if you want to fork this module do it [under your own authority](https://docs.perl6.org/language/typesystem#Versioning_and_authorship)
to avoid confusion with their official libraries.
