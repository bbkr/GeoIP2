unit class GeoIP2;

# debug flag,
# can be turned  on and off at any time
has Bool $.debug is rw;

# *.mmdb file decriptor
has IO::Handle $!handle;

# metadata with database informations
has %.metadata;

class X::DatabasePathInvalid is Exception is export { };
class X::DatabaseMetaDataNotFound is Exception is export { };

submethod BUILD ( Str:D :$path!, :$!debug = False ) {
    
    X::DatabasePathInvalid.new.throw( ) unless $path.IO ~~ :e & :f & :r;
    
    $!handle = open( $path, :bin );
    
    # extract metdata to confirm file is valid-ish
    self!find-metadata( );
    
}

#| extract metadata information
method !find-metadata {

    # constant sequence of bytes that separates IP data from metadata
    state $metadata-marker = Buf.new( 0xAB, 0xCD, 0xEF ) ~ 'MaxMind.com'.encode;

    # position cursor after last occurrence of marker
    loop {
        # jump to EOF
        FIRST $!handle.seek( 0, SeekFromEnd );
        
        # check if BOF is reached before marker is found
        X::DatabaseMetaDataNotFound.new.throw unless $!handle.tell > 0;
        
        # read one byte backwards
        $!handle.seek( -1, SeekFromCurrent );
        my $byte = $!handle.read( 1 )[0];
        $!handle.seek( -1, SeekFromCurrent );
        
        # not a potential marker start, try next byte
        next unless $byte == 0xAB;
        
        # marker found, cursor will be positioned right after it
        last if $!handle.read( $metadata-marker.elems ) == $metadata-marker;
        
        # marker not found, rewind cursor to previous position
        $!handle.seek( -$metadata-marker.elems, SeekFromCurrent );
    }
    
    %.metadata = self!decode( );
}

#| decode value at current handle position
method !decode {
    
    use experimental :pack;
    
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
    my $control-byte = $!handle.read( 1 ).unpack( 'C' );
    
    # first 3 bits of control byte describe container type
    my $type = %types{ $control-byte +> 5 };
    self!debug( :$type ) if $.debug;
    
    # extended type will map to type described by next byte
    if $type eq 'extended' {
        # TODO: add protection against unknown extended type
        my $next-byte = $!handle.read( 1 ).unpack( 'C' );
        $type = %types{ $next-byte + 7 };
        self!debug( :$type ) if $.debug;
    }
    
    my $size = self!decode-size( $control-byte );
    self!debug( :$size ) if $.debug;
    
    given $type {
        when 'array' { return self!decode-array( :$size ) }
        when 'map' { return self!decode-map( :$size ) }
        when 'utf8_string' { return self!decode-string( :$size ) }
        when 'uint16' | 'uint32' | 'uint64' { return self!decode-uint( :$size ) }
        default { die "Type $type NYI!" };
    }

}

#| check how big is next data chunk
method !decode-size ( $control-byte ) returns Int {

    # last 5 bits of control byte describe container size
    my $size = $control-byte +& 0b00011111;
    
    # size could be stored entirely within control byte
    return $size if $size < 29;

    # size is stored in next bytes
    if ( $size == 29 ) {
        return 29 + $!handle.read( 1 ).unpack( 'C' );
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

method !decode-uint ( Int:D :$size ) returns Int {
    my $out = 0;

    for ^$size {
        $out +<= 8;
        $out +|= $!handle.read( 1 ).unpack( 'C' );
    }
    
    return $out;
}

method !decode-string ( Int:D :$size ) returns Str {
    
    return $!handle.read( $size ).decode( );
}

method !decode-array ( Int:D :$size ) returns Array {
    my @out;
    
    for ^$size {
        my $value = self!decode( );
        @out.push: $value;
    }

    return @out;
}

method !decode-map ( Int:D :$size ) returns Hash {
    my %out;
    
    for ^$size {
        my $key = self!decode( );
        self!debug( :$key ) if $.debug;
        my $value = self!decode( );
        self!debug( :$value ) if $.debug;
        %out{ $key } = $value;
    }

    return %out;
}

method !debug ( *%_ ) {
    %_{ 'offset' } = $!handle.defined ?? $!handle.tell( ) !! 'unknown';
    note %_.gist;
}
