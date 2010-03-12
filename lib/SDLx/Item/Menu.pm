package SDLx::Item::Menu;
use SDL;
use SDL::Video;
use SDL::TTF;
use SDL::Color;
use Mouse;

# TODO: add default values
has 'font'         => ( is => 'ro', isa => 'Str', required => 1 );
has 'font_color'   => ( is => 'ro', isa => 'ArrayRef', 
                        default => sub { [ 255, 255, 255] }
                      );

has 'select_color' => ( is => 'ro', isa => 'ArrayRef', 
                        default => sub { [ 255, 0, 0 ] }
                      );

has 'font_size'    => ( is => 'ro', isa => 'Int', default => 24 );
has 'current'      => ( is => 'rw', isa => 'Int', default => 0 );

# TODO implement those
has 'mouse'        => ( is => 'ro', isa => 'Bool');
has 'change_sound' => ( is => 'ro', isa => 'Str' );
has 'select_sound' => ( is => 'ro', isa => 'Str' );

# internal
has '_items' => (is => 'rw', isa => 'ArrayRef', default => sub {[]} );
has '_font'  => (is => 'rw', isa => 'SDL::TTF_Font' );

has '_font_color'   => (is => 'rw', isa => 'SDL::Color' );
has '_select_color' => (is => 'rw', isa => 'SDL::Color' );

sub BUILD {
    my $self = shift;

    $self->_build_font;
}

sub _build_font {
    my $self = shift;
    $self->_font( SDL::TTF::open_font( $self->font, $self->font_size ) );

    Carp::croak 'Error opening font: ' . SDL::get_error
        unless $self->_font;

    $self->_font_color( SDL::Color->new( @{$self->font_color} ) );
    $self->_select_color( SDL::Color->new( @{$self->select_color} ) );
}

sub items {
    my ($self, @items) = @_;

    while( my ($name, $val) = splice @items, 0, 2 ) {
        push @{$self->_items}, { name => $name, trigger => $val };
    }

    return $self;
}

sub event_hook {
    my ($self, $event) = @_;

    # TODO: add mouse hooks
    if ( $event->type == SDL_KEYDOWN ) {
        my $key = $event->key_sym;

        if ($key == SDLK_DOWN) {
            $self->current( ($self->current + 1) % @{$self->_items} );
            # TODO: add change sound support
        }
        elsif ($key == SDLK_UP) {
            $self->current( ($self->current - 1) % @{$self->_items} );
            # TODO: add change sound support
        }
        elsif ($key == SDLK_RETURN or $key == SDLK_KP_ENTER ) {
            # TODO: add select sound support
            return $self->_items->[$self->current]->{trigger}->();
        }
    }

    return $self;
}

# NOTE: the update() call is here just as an example.
# SDLx::* calls should likely implement those whenever
# they need updating in each delta t.
sub update {}


sub render {
    my ($self, $screen) = @_;

    # TODO: parametrize line spacing (height)
    # and other constants used here
    my $height = 200;

    foreach my $item ( @{$self->_items} ) {
#        print STDERR 'it: ' . $item->{name} . ', s: '. $self->_items->[$self->current]->{name} . ', c: ' . $self->current . $/;
        my $color = $item->{name} eq $self->_items->[$self->current]->{name}
                  ? $self->_select_color : $self->_font_color
                  ;

        my $surface = SDL::TTF::render_text_blended(
                $self->_font, $item->{'name'}, $color
            ) or Carp::croak 'TTF render error: ' . SDL::get_error;

        SDL::Video::blit_surface(
                $surface, 
                SDL::Rect->new(0,0,$surface->w, $surface->h),
                $screen,
                SDL::Rect->new( $screen->w / 2 - 70, $height += 50, $screen->w, $screen->h),
        );
    }
}

42;
__END__

Create a simple SDL menu for your game/app:

    SDLx::Item::Menu->new->items(
        'New Game' => \&play,
        'Options'  => \&settings,
        'Quit'     => \&quit,
    );


Or customize it at will:

    SDLx::Item::Menu->new(
        topleft      => [100, 120],
        font         => 'game/data/menu_font.ttf',
        font_size    => 20,
        font_color   => [255, 0, 0], # RGB (in this case, 'red')
        select_color => [

TODO