unit class GeoIP2;

# debug flag,
# can be turned  on and off at any time
has Bool $.debug is rw;

# database informations
has %.metadata;

# *.mmdb file decriptor
has IO::Handle $!handle;

class X::PathInvalid is Exception is export { };
class X::MetaDataNotFound is Exception is export { };
class X::NodeIndexOutOfRange is Exception is export { };

submethod BUILD ( Str:D :$path!, :$!debug = False ) {
    
    X::PathInvalid.new.throw( ) unless $path.IO ~~ :e & :f & :r;
    
    $!handle = open( $path, :bin );
    
    # extract metdata to confirm file is valid-ish
    %!metadata = self.read-metadata( );
    
    # precalculate derived values
    %!metadata{ 'node_byte_size' } = ( %!metadata{ 'record_size' } * 2 / 8 ).Int;
    %!metadata{ 'search_tree_size' } = %!metadata{ 'node_count' } * %!metadata{ 'node_byte_size' };
    if %!metadata{ 'ip_version' } == 4 {
        %!metadata{ 'ipv4_start_node' } = 0;
    }
    else {
        my $index = 0;
        # for IPv4 in IPv6 subnet /96 contains 0s
        # so left node branch should be traversed 96 times
        for ^96 {
            ( $index,  ) = self.read-node( :$index );
            last if $index >= %!metadata{ 'node_count' };
        }
        %!metadata{ 'ipv4_start_node' } = $index;
    }
}

#| extract metadata information
method read-metadata ( ) returns Hash {

    # constant sequence of bytes that separates IP data from metadata
    state $metadata-marker = Buf.new( 0xAB, 0xCD, 0xEF ) ~ 'MaxMind.com'.encode;

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
    return self!decode( );
}

#| return two pointers for left and right tree branch
method read-node ( Int:D :$index! ) returns List {
    
    # negative or too big index cannot be requested
    X::NodeIndexOutOfRange.new( message => $index ).throw( )
        unless 0 <= $index < %!metadata{ 'node_count' };

    # position cursor at the beginnig of node index
    $!handle.seek( $index * %.metadata{ 'node_byte_size' }, SeekFromBeginning );
    
    # read all index bytes
    my $bytes = $!handle.read( %.metadata{ 'node_byte_size' } );
    
    # medium database,
    # most important bits of both pointers are stored in middle byte
    if %.metadata{ 'record_size' } == 28 {

        # extract left side bits 27...24 from middle byte
        my $left-pointer = $bytes[ 3 ] +> 4;
        # merge with left side bits 23...16, 15...8 and 7...0
        for 0..2 {
            $left-pointer +<= 8;
            $left-pointer +|= $bytes[ $_ ];
        }
        
        # extract right side bits 27...24 from middle byte
        my $right-pointer = $bytes[ 3 ] +& 0x0F;
        # merge with right side bits 23...16, 15...8 and 7...0
        for 4..6 {
            $right-pointer +<= 8;
            $right-pointer +|= $bytes[ $_ ];
        }

        self!debug( :$left-pointer, :$right-pointer ) if $.debug;
        
        return $left-pointer, $right-pointer;
    }
    else {
       die "Record size " ~ %.metadata{ 'record_size' } ~ " NYI!";
    }
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
    
    my $index = %.metadata{ 'ipv4_start_node' };
    
    for @bits -> $bit {
        
        # end of index or data pointer reached
        last if $index >= %.metadata{ 'node_count' };

        # check which branch of binary tree should be traversed
        my ( $left-pointer, $right-pointer ) = self.read-node( :$index );
        $index = $bit ?? $right-pointer !! $left-pointer;

        self!debug( :$index, :$bit ) if $.debug;
        
    }
    
    # IP not found
    return if $index == %.metadata{ 'node_count' };
    
    # position cursor to data section pointed by pointer
    $!handle.seek( $index - %.metadata{ 'node_count' } + %.metadata{ 'search_tree_size' } );
    
    return self!decode( );
}

#| decode value at current handle position
method !decode {
    
    # TODO: type names are meaningless,
    # numeric values can be mapped directly to decoding methods
    # to gain some performance
    state %types =
    
        # basic types
        0  => 'extended',
        1  => 'pointer',
        2  => 'utf8_string',
        3  => 'double',
        4  => 'bytes',
        5  => 'uint16',
        6  => 'uint32',
        7  => 'map',

        # extended types
        8  => 'int32',
        9  => 'uint64',
        10 => 'uint128',
        11 => 'array',
        12 => 'container',
        13 => 'end_marker',
        14 => 'boolean',
        15 => 'float'
    ;
    
    # first byte is control byte
    my $control-byte = $!handle.read( 1 )[ 0 ];
    
    # right 3 bits of control byte describe container type
    my $type = %types{ $control-byte +> 5 };
    self!debug( :$type ) if $.debug;
    
    # for pointers data is not located immediately after current cursor position
    if ( $type eq 'pointer' ) {
        
        # remember current cursor position
        # to restore it after pointer jump
        my $cursor = $!handle.tell( );
        
        # decode data from remote location in file
        $!handle.seek( self!decode-pointer( :$control-byte ), SeekFromBeginning );
        my $out = self!decode( );
        
        # restore cursor to next byte
        $!handle.seek( $cursor + 1, SeekFromBeginning );
        
        return $out;
    }
    
    # extended type will map to type described by next byte
    if $type eq 'extended' {
        # TODO: add protection against unknown extended type
        my $next-byte = $!handle.read( 1 )[ 0 ];
        $type = %types{ $next-byte + 7 };
        self!debug( :$type ) if $.debug;
    }
    
    my $size = self!decode-size( :$control-byte );
    self!debug( :$size ) if $.debug;
    
    given $type {
        when 'array' { return self!decode-array( :$size ) }
        when 'map' { return self!decode-map( :$size ) }
        when 'utf8_string' { return self!decode-string( :$size ) }
        when 'uint16' | 'uint32' | 'uint64' { return self!decode-uint( :$size ) }
        when 'double' { return self!decode-double( :$size ) }
        when 'boolean' { return self!decode-boolean( :$size ) }
        default { die "Type $type NYI!" };
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
    $pointer += %.metadata{ 'search_tree_size' } + $data-marker.bytes;
    
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

method !decode-uint ( Int:D :$size! ) returns Int {
    my $out = 0;

    for ^$size {
        $out +<= 8;
        $out +|= $!handle.read( 1 )[ 0 ];
    }
    
    return $out;
}

method !decode-double ( Int:D :$size! ) {
    
    # NYI, just skip bytes without decoding
    $!handle.read( $size );
    
    # TODO: decode IEEE754 value
    return 'NYI!'
}

method !decode-string ( Int:D :$size! ) returns Str {
    
    return $!handle.read( $size ).decode( );
}

method !decode-array ( Int:D :$size! ) returns Array {
    my @out;
    
    for ^$size {
        my $value = self!decode( );
        @out.push: $value;
    }

    return @out;
}

method !decode-map ( Int:D :$size! ) returns Hash {
    my %out;
    
    for ^$size {
        my $key = self!decode( );
        my $value = self!decode( );
        %out{ $key } = $value;
    }

    return %out;
}

method !decode-boolean ( Int:D :$size! ) returns Bool {
    
    # non zero size means True,
    # there is no additional data required to decode value
    return $size.Bool;
}

method !debug ( *%_ ) {
    %_{ 'offset' } = $!handle.defined ?? $!handle.tell( ) !! 'unknown';
    note %_.gist;
}
