
package Zircon::Protocol::XML;

use strict;
use warnings;

use feature qw( switch );

# XML creation

sub request_xml {
    my ($self, $command, $view, $request) = @_;
    my $request_body_xml =
        defined $request ? _element_xml(@{$request}) : undef;
    my $request_element_xml = _element_xml(
        'request', {
            'command' => $command,
            'view'    => $view,
        }, $request_body_xml);
    my $app_id = $self->app_id;
    my $clipboard_id = $self->connection->remote_selection_id;
    my $request_id = $self->{'request_id'}++;
    my $zmap_element_xml = _element_xml(
        'zmap', {
            'version'      => '2.0',
            'type'         => 'request',
            'app_id'       => $app_id,
            'clipboard_id' => $clipboard_id,
            'request_id'   => $request_id,
        }, $request_element_xml);
    return $zmap_element_xml;
}

sub reply_xml {
    my ($self, $request_id, $command, $reply) = @_;
    my ($status, $reply_body) = @{$reply};
    my ($return_code, $reason) =
        defined $status ? @{$status} : ( 'ok' );
    my $reply_body_xml = _element_xml(@{$reply_body});
    my $reply_element_xml = _element_xml(
        'reply', {
            'command'     => $command,
            'return_code' => $return_code,
            'reason'      => $reason,
        }, $reply_body_xml);
    my $app_id = $self->app_id;
    my $clipboard_id = $self->connection->local_selection_id;
    my $zmap_element_xml = _element_xml(
        'zmap', {
            'version'      => '2.0',
            'type'         => 'reply',
            'app_id'       => $app_id,
            'clipboard_id' => $clipboard_id,
            'request_id'   => $request_id,
        }, $reply_element_xml);
    return $zmap_element_xml;
}

sub _element_xml {
    my ($tag, $attribute_hash, $content_xml) = @_;
    my $tag_xml = join ' ', $tag, map {
        _attribute_xml($_, $attribute_hash->{$_});
    } keys %{$attribute_hash};
    return defined $content_xml
        ? sprintf "<%s>\n%s\n</%s>", $tag_xml, $content_xml, $tag
        : sprintf "<%s />", $tag_xml;
}

sub _attribute_xml {
    my ($key, $value) = @_;
    defined $value or return;
    $value =~ s/&/&amp;/g;
    $value =~ s/"/&quot;/g;
    $value =~ s/</&lt;/g;
    $value =~ s/>/&gt;/g;
    return sprintf '%s="%s"', $key, $value;
}

# XML parsing

my @request_parse_parameter_list = (
    'tag_expected' => 'request',
    'attribute_required' => [ qw(
        command
        ) ],
    'attribute_used' => [ qw(
        command
        view
        ) ],
    );

sub request_xml_parse {
    my ($self, $request_xml) = @_;
    my ($request_id, $protocol_attribute_hash, $content_xml) =
        @{_protocol_xml_parse($request_xml)};
    my $content_parse =
        _content_xml_parse($content_xml, @request_parse_parameter_list);
    my $parse = [ $request_id, @{$content_parse} ];
    return $parse;
}

my @reply_parse_parameter_list = (
    'tag_expected' => 'reply',
    'attribute_required' => [ qw(
        command
        return_code
        ) ],
    'attribute_used' => [ qw(
        command
        return_code
        reason
        view
        ) ],
    );

sub reply_xml_parse {
    my ($self, $reply_xml) = @_;
    my ($request_id, $protocol_attribute_hash, $content_xml) =
        @{_protocol_xml_parse($reply_xml)};
    my $content_parse =
        _content_xml_parse($content_xml, @reply_parse_parameter_list);
    my $parse = [ $request_id, @{$content_parse} ];
    return $parse;
}

sub _protocol_xml_parse {
    my ($xml) = @_;

    my ($tag, $attribute_hash, $content_xml) = @{_unique_element($xml)};
    my $tag_expected = 'zmap';
    $tag eq $tag_expected
        or die sprintf
        "invalid protocol tag: '%s': expected: '%s'"
        , $tag, $tag_expected;

    my $request_id = $attribute_hash->{'request_id'};
    defined $request_id
        or die "missing protocol attribute: 'request_id'";

    my $parse = [ $request_id, $attribute_hash, $content_xml ];

    return $parse;
}

sub _content_xml_parse {
    my ($xml, %parameter_hash) = @_;

    my (
        $tag_expected,
        $attribute_required,
        $attribute_used,
        ) =
        @parameter_hash{qw(
        tag_expected
        attribute_required
        attribute_used
        )};

    my ($tag, $attribute_hash, $body_xml) = @{ _unique_element($xml) };
    $tag eq $tag_expected
        or die sprintf
        "invalid content tag: '%s': expected: '%s'"
        , $tag, $tag_expected;

    for my $attribute (@{$attribute_required}) {
        (defined $attribute_hash->{$attribute})
            or die sprintf "missing attribute in %s tag: '%s'"
            , $tag, $attribute;
    }

    my $body = defined $body_xml ? _xml_parse($body_xml) : undef;
    my $parse = [ @{$attribute_hash}{@{$attribute_used}}, $body ];

    return $parse;
}

sub _unique_element {
    my ($element_xml) = @_;
    my $element;
    _each_element(
        $element_xml,
        sub {
            defined $element and die 'multiple elements';
            ($element) = @_;
        });
    defined $element or die 'missing element';
    return $element;
}

sub _xml_parse {
    my ($xml) = @_;
    return $xml =~ /[<>]/ ? _xml_element_set_parse($xml) : _xml_string_parse($xml);
}

sub _xml_element_set_parse {
    my ($xml) = @_;
    my $element_list = [ ];
    _each_element(
        $xml,
        sub {
            my ($element) = @_;
            my $body_xml = pop @{$element};
            my $body = defined $body_xml ? _xml_parse($body_xml) : undef;
            push @{$element}, $body;
            push @{$element_list}, $element;
        });
    return $element_list;
}

sub _xml_string_parse {
    my ($xml) = @_;
    local $_ = $xml;
    _xml_unescape();
    return $_;
}

my $element_list_xml_pattern = qr!
    \G
    (?:[[:space:]]*)                                        # leading space
    (?: # alternative #1 - element 
        < [[:space:]]* ([[:alpha:]_]+)                      # begin open tag
        ((?:[[:space:]]*[[:alpha:]_]+="[^"]*")*)            # attributes
        [[:space:]]*
        (?:
            / [[:space:]]* >                                # end empty tag
        |
            >                                               # end open tag
            (.*)                                            # element body
            < [[:space:]]* / [[:space:]]* \1 [[:space:]]* > # close tag
        )
    |   # alternative #2 - garbage
        (.*)\z
    )
    !xms;

my $attributes_xml_pattern = qr!
    ([[:alpha:]_]+)="([^"]*)"
    !xms;

# this *is* used in _xml_unescape but perlcritic cannot see code in s///e
sub _xml_entity { ## no critic(Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($name) = @_;
    for ($name) {
        when ('lt')   { return '<'; }
        when ('gt')   { return '>'; }
        when ('quot') { return '"'; }
        when ('amp')  { return '&'; }
    }
    die sprintf "unknown XML entity: '%s'", $name;
}

sub _xml_unescape {
    s/&#([[:digit:]]+);/chr $1/eg;
    s/&([[:alpha:]]+);/_xml_entity $1/eg;
    return;
}

sub _each_element {
    my ($element_list_xml, $callback) = @_;
    while ( $element_list_xml =~ /$element_list_xml_pattern/gc ) {
        my ($tag, $attributes_xml, $body_xml, $garbage) =
            ($1, $2, $3, $4);
        if ( defined $garbage ) {
            return if $garbage eq '';
            die 'trailing garbage';
        }
        my $attributes = {
            $attributes_xml =~ /$attributes_xml_pattern/g,
        };
        _xml_unescape for values %{$attributes};
        my $element = [ $tag, $attributes, $body_xml ];
        $callback->($element);
    }
    return;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk