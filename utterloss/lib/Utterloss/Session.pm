
package Utterloss::Session;

use strict;
use warnings;

use Scalar::Util qw( weaken );
use File::Copy qw( move );
use File::Basename qw( basename );
use Try::Tiny;

use Tk::Toplevel;
use Tk::Pane;
use Tk::Button;

use Hum::Ace::LocalServer;

use Zircon::ZMap;

my $utterloss_app_id = 'Utterloss';

sub new {
    my ($pkg, @args) = @_;
    my $new = { };
    bless $new, $pkg;
    $new->_init(@args);
    return $new;
}

sub _init {
    my ($self, $utterloss, $args) = @_;

    $self->{'utterloss'} = $utterloss;
    weaken $self->{'utterloss'};
    ($self->{'session_dir_orig'}) =
        @{$args}{qw( -session_dir )};
    ($self->{'session_dir'}) =
        $self->session_dir_orig =~ /\A(.*)\.done\z/
        or die "BUG!!!\n";

    $self->window_create;
    $self->feature_pane_create;
    $self->close_button_create;
    $self->zmap_view_create;

    return;
}

sub window_create {
    my ($self) = @_;
    my $window = $self->{'window'} =
        $self->utterloss->window->Toplevel;
    my ($session_name) = basename $self->session_dir;
    my $title = "Session: ${session_name}";
    $window->title($title);
    return;
}

sub feature_pane_create {
    my ($self) = @_;
    $self->{'feature_pane'} =
        $self->window->Scrolled(
            'Pane',
            '-scrollbars' => 'e',
            '-sticky'     => 'nswe',
        )
        ->pack(
            '-side'   => 'top',
            '-expand' => 1,
            '-fill'   => 'both',
        );
    return;
}

sub close_button_create {
    my ($self) = @_;
    $self->window->Button(
        '-text' => 'Close',
        '-command' => sub { $self->_close; },
        )
        ->pack(
        '-side' => 'top',
        '-fill' => 'both');
    return;
}

sub _close {
    my ($self) = @_;
    $self->window->destroy;
    return;
}

my $zmap_stanza_pattern = qr!
    ^\[ZMap\]$
    (.*?)
    (?:^\[|\z)
    !xms;

my $zmap_key_value_pattern = qr!
    ^
    [[:blank:]]*               # key
    ([^[:space:]]+)
    [[:blank:]]*=[[:blank:]]*  # =
    (.*)                       # value
    $
    !xm;

my $zmap_config_global = '
[ZMap]
show-mainwindow = false
';

sub zmap_view_create {
    my ($self) = @_;
    my $session_dir = $self->session_dir;
    move $self->session_dir_orig, $session_dir;
    try {
        my $selection_id =
            sprintf 'utterloss_%s_%06d'
            , $self->window->id, int(rand(1_000_000));
        my $zmap_dir = "${session_dir}/ZMap";

        my $ace = Hum::Ace::LocalServer->new($session_dir);
        $ace->server_executable('sgifaceserver');
        my $ace_url = sprintf
            'acedb://%s:%s@%s:%d'
            , $ace->user, $ace->pass, $ace->host, $ace->port;

        my $config_path = "${zmap_dir}/ZMap";
        my $config = _zmap_config_get($config_path);
        my ($zmap_stanza) = $config =~ /$zmap_stanza_pattern/
            or die "failed to locate the ZMap configuration stanza";
        my $zmap_config = { $zmap_stanza =~ /$zmap_key_value_pattern/g, };
        my $config_new = _zmap_config_new($config, $zmap_config, $ace_url);
        _zmap_config_save($config_path, $config_new);

        $ace->start_server()
            or die "the ace server failed to start\n";
        $ace->ace_handle(1)
            or die "the ace server failed to connect\n";

        my $arg_list = [
            '--conf_dir' => $config_path,
        ];
        my $zmap =
            Zircon::ZMap->new(
                '-program' => $self->utterloss->program,
                '-context' => $self->utterloss->zircon_context,
                '-app_id'  => $utterloss_app_id,
                '-arg_list'=> $arg_list,
                '-rolechange_wait' => 1,
            );

        my ($name, $start, $end) =
            @{$zmap_config}{qw( sequence start end )};

        my $zmap_view =
            $zmap->new_view(
                '-name'  => $name,
                '-start' => $start,
                '-end'   => $end,
                '-config_file' => $config_path,
                '-handler' => $self,
                );

        $self->{'ace'} = $ace;
        $self->{'zmap_view'} = $zmap_view;
    }
    catch {
        $self->finish;
        die $_;
    };
    return;
}

sub zircon_zmap_view_features_loaded {
    my ($self, $status, $message, @featureset_list) = @_;
    for my $featureset (@featureset_list) {
        $self->featureset_add($featureset);
    }
    return;
}

sub featureset_add {
    my ($self, $featureset) = @_;
    $self->feature_pane->Label(
        '-text' => $featureset)
        ->pack(
        '-side' => 'top',
        '-fill' => 'both');
    return;
}

sub finish {
    my ($self) = @_;
    delete $self->{'zmap_view'};
    delete $self->{'ace'};
    move $self->session_dir, $self->session_dir_orig
        if -d $self->session_dir;
    return;
}

sub _zmap_config_get {
    my ($config_path) = @_;
    local $/ = undef;
    open my $config_read_h, '<', $config_path
        or die "open() failed: $!\n";
    my $config = <$config_read_h>;
    close $config_read_h
        or die "close() failed: $!\n";
    return $config;
}

sub _zmap_config_save {
    my ($config_path, $config) = @_;
    open my $config_write_h, '>', $config_path
        or die "open() failed: $!\n";
    print $config_write_h $config;
    close $config_write_h
        or die "close() failed: $!\n";
    return;
}

sub _zmap_config_new {
    my ($config, $zmap_config, $ace_url) = @_;

    my $source_list = $zmap_config->{'sources'}
        or die "failed to locate the source list";

    my ($sequence) = split /[[:blank:]]*;[[:blank:]]*/, $source_list;
    printf "sequence: %s\n", $sequence;

    $config =~ s/(
    ^\[${sequence}\]$
    .*?
    (?=^\[|\z)
    )/_zmap_sequence_stanza_new($1, $ace_url)/xmse;

    return $config;
}

sub _zmap_sequence_stanza_new { ## no critic(Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($stanza, $ace_url) = @_;
    $stanza =~ s/^(url=).*/$1${ace_url}/m;
    return $stanza;
}

# attributes

sub utterloss {
    my ($self) = @_;
    my $utterloss = $self->{'utterloss'};
    return $utterloss;
}

sub window {
    my ($self) = @_;
    my $window = $self->{'window'};
    return $window;
}

sub feature_pane {
    my ($self) = @_;
    my $feature_pane = $self->{'feature_pane'};
    return $feature_pane;
}

sub zmap_view {
    my ($self) = @_;
    my $zmap_view = $self->{'zmap_view'};
    return $zmap_view;
}

sub session_dir_orig {
    my ($self) = @_;
    my $session_dir_orig = $self->{'session_dir_orig'};
    return $session_dir_orig;
}

sub session_dir {
    my ($self) = @_;
    my $session_dir = $self->{'session_dir'};
    return $session_dir;
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
