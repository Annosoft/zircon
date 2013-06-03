
package Zircon::Tk::Context;

use strict;
use warnings;

use Carp qw( croak cluck );
use Tk::Xlib;
use Zircon::Tk::Selection;
use base 'Zircon::Trace';
our $ZIRCON_TRACE_KEY = 'ZIRCON_CONTEXT_TRACE';


sub new {
    my ($pkg, %args) = @_;
    my $new = { };
    bless $new, $pkg;
    $new->init(\%args);
    return $new;
}

sub init {
    my ($self, $args) = @_;
    my $widget = $args->{'-widget'};
    defined $widget or die 'missing -widget argument';
    $self->{'widget'} = $widget;
    $self->zircon_trace;
    return;
}

# platform
sub platform { return 'Tk'; }

# selections

sub selection_new {
    my ($self, @args) = @_;
    $self->zircon_trace('for (%s)', "@args");
    my $selection =
        Zircon::Tk::Selection->new(
            '-platform' => $self->platform,
            '-widget'   => $self->widget,
            @args);
    return $selection;
}

# timeouts

sub timeout {
    my ($self, @args) = @_;

    my $w = $self->widget;
    Tk::Exists($w)
        or croak "Attempt to set timeout with destroyed widget";
    my $timeout_handle = $w->after(@args);
    $self->zircon_trace('configured (%d millisec)', $args[0]);
    return $timeout_handle;
}

# waiting

sub waitVariable {
    my ($self, $var) = @_;
    $self->zircon_trace('enter for %s=%s', $var, $$var);
    my $w = $self->widget;
    Tk::Exists($w)
        or croak "Attempt to waitVariable with destroyed widget";
    $w->waitVariable($var);
    Tk::Exists($w)
        or cluck "Widget $w destroyed during waitVariable";
    $self->zircon_trace('exit with %s=%s', $var, $$var);
    return;
}

# attributes

sub widget {
    my ($self) = @_;
    my $widget = $self->{'widget'};
    return $widget;
}

sub widget_xid {
    my ($self) = @_;
    return $self->widget->id;
}

# other app's windows

sub window_exists {
    my ($self, $win_id) = @_;
    my $widget = $self->{'widget'};

    my $w = $self->widget;
    Tk::Exists($w)
        or croak "Attempt to check window_exists with destroyed widget";

    my $win;
    if (ref($win_id)) {
        # assume it is a Window from Tk::Xlib
        $win = $win_id;
    } else {
        $win_id = hex($win_id) if $win_id =~ /^0x/;
        $win = \$win_id;
        # there is no constructor, they come from Tk.xs
        bless $win, 'Window'; # no critic(
    }

    my ($root, $parent);
    return try {
        # see e.g. Xlib/tree_demo in perl-tk
        $w->Display->XQueryTree($win, $root, $parent);
        return defined $root;
    } catch {
        die "XQueryTree died unexpectedly: $_"
          unless m{\bBadWindow\b};
        warn "$self: I see the window is gone.\n";
        return 0;
    };
}


# tracing

sub zircon_trace_prefix {
    my ($self) = @_;
    return sprintf('Z:T:Context: widget=%s', $self->widget->PathName);
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
