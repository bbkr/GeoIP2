unit class GeoIP2;

# only for IEEE conversions
use NativeCall;

# debug flag,
# can be turned  on and off at any time
has Bool $.debug is rw;

# database informations
has Version     $.binary-format-version;
has DateTime    $.build-timestamp;
has Str         $.database-type;
has             %!descriptions;
has Version     $.ip-version;
has Int         $.ipv4-start-node;
has Set         $.languages;
has Int         $.node-byte-size;
has Int         $.node-count;
has Int         $.record-size;
has Int         $.search-tree-size;

# *.mmdb file decriptor
has IO::Handle $!handle;

class X::PathInvalid is Exception is export { };
class X::MetaDataNotFound is Exception is export { };
class X::NodeIndexOutOfRange is Exception is export { };

submethod BUILD ( Str:D :$path!, :$!debug = False ) {
    
    X::PathInvalid.new.throw( ) unless $path.IO ~~ :e & :f & :r;
    
    $!handle = open( $path, :bin );
    
    # extract metdata to confirm file is valid-ish
    with self!read-metadata( ) {
        $!binary-format-version = Version.new(
            .{ 'binary_format_major_version', 'binary_format_minor_version' }.join( '.' )
        );
        $!build-timestamp   = DateTime.new( .{ 'build_epoch' } );
        $!database-type     = .{ 'database_type' };
        %!descriptions      = .{ 'description' };
        $!ip-version        = Version.new( .{ 'ip_version' } );
        $!languages         = .{ 'languages' }.map( { .uc } ).Set;
        $!node-count        = .{ 'node_count' };
        $!record-size       = .{ 'record_size' };
    }
    
    # precalculate derived values for better performance
    $!node-byte-size    = ( $!record-size * 2 / 8 ).Int;
    $!search-tree-size  = $!node-count * $!node-byte-size;
    $!ipv4-start-node   = 0;
    if $!ip-version ~~ v6 {
        # for IPv4 in IPv6 subnet /96 contains 0s
        # so left node branch should be traversed 96 times
        for ^96 {
            ( $!ipv4-start-node,  ) = self.read-node( index => $!ipv4-start-node );
            last if $!ipv4-start-node >= $!node-count;
        }
    }
}

#| return description in requested language ( if available )
method description ( Str:D $language = 'EN' ) {

    return %!descriptions{ $language.lc };
}

#| extract metadata information
method !read-metadata ( ) returns Hash {

    # constant sequence of bytes that separates IP data from metadata
    state $metadata-marker = Buf.new( 0xAB, 0xCD, 0xEF ) ~ 'MaxMind.com'.encode( );

    # position cursor after last occurrence of marker
    loop {
        
        # jump to EOF
        FIRST $!handle.seek( 0, SeekFromEnd );
        
        # check if BOF is reached before marker is found
        X::MetaDataNotFound.new.throw unless $!handle.tell > 0;
        
        # read one byte backwards
        $!handle.seek( -1, SeekFromCurrent );
        my $byte = $!handle.read( 1 )[ 0 ];
        $!handle.seek( -1, SeekFromCurrent );
        
        # not a potential marker start, try next byte
        next unless $byte == 0xAB;
        
        # marker found, cursor will be positioned right after it
        last if $!handle.read( $metadata-marker.elems ) == $metadata-marker;
        
        # marker not found, rewind cursor to previous position
        $!handle.seek( -$metadata-marker.elems, SeekFromCurrent );
    }
    
    # decode metadata section into map structure
    return self!decode-value( );
}

#| return two pointers for left and right tree branch
method read-node ( Int:D :$index! ) returns List {
    my ( $left-pointer, $right-pointer );
    
    # negative or too big index cannot be requested
    X::NodeIndexOutOfRange.new( message => $index ).throw( )
        unless 0 <= $index < $!node-count;

    # position cursor at the beginnig of node index
    $!handle.seek( $index * $!node-byte-size, SeekFromBeginning );
    
    # read all index bytes
    my $bytes = $!handle.read( $!node-byte-size );
    
    # small database
    if $!record-size == 24 {
        
        # extract left side bits 23...16, 15...8 and 7...0 from left bytes
        $left-pointer = 0;
        for 0..2 {
            $left-pointer +<= 8;
            $left-pointer +|= $bytes[ $_ ];
        }
        
        # extract right side bits 23...16, 15...8 and 7...0 from right bytes
        $right-pointer = 0;
        for 3..5 {
            $right-pointer +<= 8;
            $right-pointer +|= $bytes[ $_ ];
        }
    }
    # medium database,
    # most important bits of both pointers are stored in middle byte
    elsif $!record-size == 28 {

        # extract left side bits 27...24 from middle byte
        $left-pointer = $bytes[ 3 ] +> 4;
        # merge with left side bits 23...16, 15...8 and 7...0 from left bytes
        for 0..2 {
            $left-pointer +<= 8;
            $left-pointer +|= $bytes[ $_ ];
        }
        
        # extract right side bits 27...24 from middle byte
        $right-pointer = $bytes[ 3 ] +& 0x0F;
        # merge with right side bits 23...16, 15...8 and 7...0 from right bytes
        for 4..6 {
            $right-pointer +<= 8;
            $right-pointer +|= $bytes[ $_ ];
        }
    }
    else {
       die "Record size " ~ $!record-size ~ " NYI!";
    }
    
    self!debug( :$left-pointer, :$right-pointer ) if $.debug;
    
    return $left-pointer, $right-pointer;
}

method read-location ( Str:D :$ip! where / ^ [\d ** 1..3] ** 4 % '.' $ / ) {

    # convert octet form of IP into array of bits in big-endian order
    my @bits;
    for $ip.comb( /\d+/ ) {
        
        # convert to bits
        my @octet-bits = .Int.polymod( 2 xx * ).reverse;
        
        # append to flat bit array, zero pad byte from left if needed
        push @bits, |( 0 xx ( 8 - +@octet-bits ) ), |@octet-bits;
    }
    self!debug( :@bits ) if $.debug;
    
    my $index = $!ipv4-start-node;
    
    for @bits -> $bit {
        
        # end of index or data pointer reached
        last if $index >= $!node-count;

        # check which branch of binary tree should be traversed
        my ( $left-pointer, $right-pointer ) = self.read-node( :$index );
        $index = $bit ?? $right-pointer !! $left-pointer;

        self!debug( :$index, :$bit ) if $.debug;
        
    }
    
    # IP not found
    return if $index == $!node-count;
    
    # position cursor to data section pointed by pointer
    $!handle.seek( $index - $!node-count + $!search-tree-size );
    
    return self!decode-value( );
}

#| decode value at current handle position
method !decode-value ( ) {
    
    # first byte is control byte
    my $control-byte = $!handle.read( 1 )[ 0 ];
    
    # right 3 bits of control byte describe container type
    my $type = $control-byte +> 5;
    self!debug( :$type ) if $.debug;
    
    # for pointers data is not located immediately after current cursor position
    if $type == 1 {
        
        # remember current cursor position
        # to restore it after pointer jump
        my $cursor = $!handle.tell( );
        
        # decode data from remote location in file
        $!handle.seek( self!decode-pointer( :$control-byte ), SeekFromBeginning );
        my $out = self!decode-value( );
        
        # restore cursor to next byte
        $!handle.seek( $cursor + 1, SeekFromBeginning );
        
        return $out;
    }
    
    # extended type will map to type described by next byte
    if $type == 0 {
        $type = $!handle.read( 1 )[ 0 ] + 7;
        self!debug( :$type ) if $.debug;
    }
    
    my $size = self!decode-size( :$control-byte );
    self!debug( :$size ) if $.debug;
    
    given $type {
        when 2 { return self!decode-string( :$size ) }
        when 5 | 6 | 9 | 10 { return self!decode-unsigned-integer( :$size ) }
        when 8 { return self!decode-signed-integer( :$size ) }
        when 3 | 15 { return self!decode-floating-number( :$size ) }
        when 14 { return self!decode-boolean( :$size ) }
        when 4 { return self!decode-raw-bytes( :$size ) }
        when 11 { return self!decode-array( :$size ) }
        when 7 { return self!decode-hash( :$size ) }
        default {
            X::NYI.new( feature => "Value of $type code" ).throw( )
        }
    }

}

method !decode-pointer ( Int:D :$control-byte! ) returns Int {
    my $pointer;
    
    # constant sequence of bytes that separates nodes from data
    state $data-marker = Buf.new( 0x00 xx 16 );
    
    # calculate pointer type
    # located on bits 4..3 of control byte
    my $type = ( $control-byte +& 0b00011000 ) +> 3;
    
    # for "small" pointers bits 2..0 of control byte are used
    if $type ~~ 0 | 1 | 2 {
        $pointer = $control-byte +& 0b00000111;
    }
    # for "big" pointer control byte bits are ignored
    else {
        $pointer = 0;
    }
    
    # type maps directly to amount of following bytes
    # required to construct pointer
    for $!handle.read( $type + 1 ) -> $byte {
        $pointer +<= 8;
        $pointer +|= $byte;
    }
    
    # some types have fixed value added
    given $type {
        when 1 { $pointer += 2048 }
        when 2 { $pointer += 526336 }
    }        
    
    # pointer starts at beginning of data section
    $pointer += $!search-tree-size + $data-marker.bytes;
    
    self!debug( :$pointer ) if $.debug;
    
    return $pointer;
}

#| check how big is next data chunk
method !decode-size ( Int:D :$control-byte! ) returns Int {

    # last 5 bits of control byte describe container size
    my $size = $control-byte +& 0b00011111;
    
    # size could be stored entirely within control byte
    return $size if $size < 29;

    # size is stored in next bytes
    if ( $size == 29 ) {
        return 29 + $!handle.read( 1 )[ 0 ];
    }
    
    die "Size $size NYI!";
    
    # elsif ( $size == 30 ) {
    #     $size = 285 + unpack( 'n', $buffer );
    # }
    # else {
    #     $size = 65821 + unpack( 'N', $self->_zero_pad_left( $buffer, 4 ) );
    # }
    #
    # return ( $size, $offset + $bytes_to_read );
}

method !decode-unsigned-integer ( Int:D :$size! ) returns Int {
    my $out = 0;
    
    # zero size means value 0
    return $out unless $size;
    
    for $!handle.read( $size ) -> $byte {
        $out +<= 8;
        $out +|= $byte;
    }
    
    return $out;
}

method !decode-floating-number ( Int:D :$size! ) {
    
    my $bytes = $!handle.read( $size );
    
    # native casting is used to convert Buf to IEEE format
    # so if local architecture does not match big endian file format
    # then byte order must be reversed
    state $is-little-endian = nativecast(
        CArray[ uint8 ], CArray[ uint32 ].new( 1 )
    )[ 0 ] == 0x01;
    $bytes .= reverse( ) if $is-little-endian;
    
    given $size {
        when 4 { return nativecast( Pointer[ num32 ], $bytes ).deref( ) }
        when 8 { return nativecast( Pointer[ num64 ], $bytes ).deref( ) }
        default {
            X::NYI.new( feature => "IEEE754 of $size bytes" ).throw( )
        }
    }
}

method !decode-string ( Int:D :$size! ) returns Str {
    
    return '' unless $size;
    return $!handle.read( $size ).decode( );
}

method !decode-array ( Int:D :$size! ) returns Array {
    my @out;
    
    for ^$size {
        my $value = self!decode-value( );
        @out.push: $value;
    }

    return @out;
}

method !decode-hash ( Int:D :$size! ) returns Hash {
    my %out;
    
    for ^$size {
        my $key = self!decode-value( );
        my $value = self!decode-value( );
        %out{ $key } = $value;
    }

    return %out;
}

method !decode-boolean ( Int:D :$size! ) returns Bool {
    
    # non zero size means True,
    # there is no additional data required to decode value
    return $size.Bool;
}

method !decode-raw-bytes ( Int:D :$size! ) returns Buf {
    
    return Buf.new unless $size;
    return $!handle.read( $size );
}

method !decode-signed-integer ( Int:D :$size! ) returns Int {
    my $out = 0;
    
    return $out unless $size;
    
    my $bytes = $!handle.read( $size );
    
    # two's complement format - leftmost bit decides about sign
    my $sign;
    if $bytes[0] +& 0b10000000 == 128 {
        $sign = -1;
    }
    else {
        $sign = 1;
    }

    for $bytes.list -> $byte {
        $out +<= 8;
        $out +|= $sign == 1 ?? $byte !! $byte +^ 0b11111111;
    }

    return $out if $sign == 1;
    return -( $out + 1 );
}


method !debug ( *%_ ) {
    %_{ 'offset' } = $!handle.defined ?? $!handle.tell( ) !! 'unknown';
    note %_.gist;
}
