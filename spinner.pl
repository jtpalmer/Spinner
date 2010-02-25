#!/usr/bin/perl

package Wheel;
use Mouse;

has 'x'       => ( is => 'ro', isa => 'Int', required => 1 );
has 'y'       => ( is => 'ro', isa => 'Int', required => 1 );
has 'size'    => ( is => 'ro', isa => 'Int', default => 60 );
has 'color'   => ( is => 'rw', default => undef );
has 'visited' => ( is => 'rw', default => undef );

has 'surface' => ( is => 'rw', isa => 'SDL::Surface' );

has 'speed' => ( is  => 'rw', isa => 'Num',
              default => sub { return rand(10)/rand(100) + 0.3 }
            );

# Blit the particles surface to the app in the right location
sub draw {
    my ($self, $app) = @_;

    my $new_part_rect = SDL::Rect->new( 0, 0, $self->size, $self->size );

    SDL::Video::blit_surface(
        $self->surface,
        $new_part_rect,
        $app,
        SDL::Rect->new(
            $self->x - ( $self->size / 2 ), $self->y - ( $self->size / 2 ),
            $app->w, $app->h
        )
    );
}


package Ball;
use Mouse;

has 'x'       => ( is => 'rw', isa => 'Num', default => 0  );
has 'y'       => ( is => 'rw', isa => 'Num', default => 0  );
has 'size'    => ( is => 'ro', isa => 'Int', default => 25 );
has 'rad'     => ( is => 'rw', isa => 'Num', default => 0  );
has 'color'   => ( is => 'ro', default => 0xFF0000FF );
has 'n_wheel' => ( is => 'rw', isa => 'Int', default => 0  );
has 'old_wheel' => ( is => 'rw', isa => 'Int', default => 0  );

has 'surface' => ( is => 'rw', isa => 'SDL::Surface' );

has 'vx' => ( is  => 'rw', isa => 'Num', default => 0 );
has 'vy' => ( is  => 'rw', isa => 'Num', default => 0 );


package main;

use strict;
use warnings;

use SDL;
use SDL::Video;
use SDL::Surface;
use SDL::Rect;
use SDL::Events;
use SDL::Event;
use SDL::Time;
use SDL::Color;
use SDL::GFX::Primitives;

use Data::Dumper;
use Carp;

my $DEBUG = 0;

#Initing video
#Die here if we cannot make video init
croak 'Cannot init video ' . SDL::get_error()
  if ( SDL::init(SDL_INIT_VIDEO) == -1 );

#Make our display window
#This is our actual SDL application window
my $app = SDL::Video::set_video_mode( 800, 600, 32,
    SDL_HWSURFACE | SDL_DOUBLEBUF | SDL_HWACCEL  );

croak 'Cannot init video mode 800x600x32: ' . SDL::get_error() if !($app);

#Some global variables used thorugh out the game
my $app_rect = SDL::Rect->new( 0, 0, 800, 600 );
my $fps = 30;

my $ball = Ball->new;
$ball->surface( init_surface( $ball->size, $ball->color ) );

# The surface of the background
my $bg_surf = init_bg_surf($app);

# The actual particles that we see bouncing around
# particles are defined as hashes
my $particles = [];
my $particles_left = 0;

#The shots we have made in each level
my @shots;

#Our level counter
my $level = 7;

my @level_map = (
    [ 200, 300 ],
    [ 200, 150 ],
    [ 400, 150 ],
    [ 600, 150 ],
    [ 200, 600-150 ],
    [ 400, 600-150 ],
    [ 600, 600-150 ],
    [ 600, 300 ]
);

my $quit = 0;

#continue until we see the $quit flag turn on that way we grace fully exit
while ( !$quit ) {
    warn 'main' if $DEBUG;

    #START our level

    $particles = [];    #Empty our particles new level
    @shots = ();        #Empty the shots we may have

    # create our spinning wheels
    foreach my $coord (@level_map) {
        my $wheel = Wheel->new( x => $coord->[0], y => $coord->[1] );
        $wheel->surface( init_surface($wheel->size, $wheel->color) );

        push @{$particles}, $wheel;
    }
    $particles_left = @{$particles};

    $ball->n_wheel( int( rand($#{$particles})) );

    # Get an event object to snapshot the SDL event queue
    my $event = SDL::Event->new();

    # SDL time is recorded in ticks,
    # Ticks are the  milliseconds since the SDL library was loaded into memory
    my $time = SDL::get_ticks();

    # This is our level continue flag
    my $cont = 1;

    # Init some level globals for time calculations
    my ( $dt, $t, $accumulator, $cur_time ) = ( 0.001, 0, 0, SDL::get_ticks() );

    #Keep a copy of the cur_time for Frames per Rate calculations
    my $init_time = $cur_time;

    #Keep a count of number of frames
    my $frames = 0;

    #Our level game loop
    while ( $cont && !$quit ) {

        while ( SDL::Events::poll_event($event) )
        {    #Get all events from the event queue in our event

            #If we have a quit event i.e click on [X] trigger the quit flage
            if ( $event->type == SDL_QUIT ) {
                $quit = 1;
            }
            elsif ( $event->type == SDL_KEYDOWN )
            {
                check_ball_release() if $event->key_sym == SDLK_SPACE;
                $quit = 1 if $event->key_sym == SDLK_ESCAPE;
                SDL::Video::wm_toggle_fullscreen( $app ) if $event->key_sym == SDLK_f;
            }
            warn 'event' if $DEBUG;

        }

        warn 'level' if $DEBUG;

        #Get a new time for use now
        my $new_time = SDL::get_ticks();

        #Check out how much time we have lost in calculations
        my $delta_time = $new_time - $cur_time;

        #if our delta_time is too fast we can skip this time
        #or we will have jitters in our animation
        next if ( $delta_time <= 0.0 );

        #set our new cur_time for the next calulation of delta time
        $cur_time = $new_time;

       #accumulate our delta_time. This is like our queue for back log animation
        $accumulator += $delta_time;

        # release the time in $dt amount of time so we have smooth animations
        while ( $accumulator >= $dt && !$quit ) {

            # update our particle locations base on dt time
            # (x,y) = dv*dt
            iterate_step($dt);

            #dequeue our time accumulator
            $accumulator -= $dt;

            #update how much real time we have animated
            $t += $dt;
            warn 'acc' if $DEBUG;
        }

        #Checkout our frames per seconds

        my $fps = $frames / ( ( SDL::get_ticks() - $init_time ) / 1000 );

        #If we are updating too fast we slow down
        #This way the X Draws don't kill our user's computer
        while ( $fps > 30 && !$quit ) {
            $fps = $frames / ( ( SDL::get_ticks() - $init_time ) / 1000 );
            SDL::delay(10);
            warn 'fps' if $DEBUG;
        }

        #If our fps starts to suffer we update our $dt,
        #this way more movement for less time
        if ( $fps < ( 30 - $dt ) ) {
            $dt += ( 30 - $fps ) * 0.1;
        }

        #Update our view and count our frames
        draw_to_screen( $fps, $level );
        $frames++;

        # Check if we have won this level!
        $cont = check_win($init_time);
    }

}

# Calculate the new velocities
sub iterate_step {
    my $dt = shift;
   
    if ( $ball->n_wheel != -1 ) {   #stuck on a wheel
        my $wheel = $particles->[ $ball->n_wheel ];
        return unless $wheel;

        $ball->rad( ($ball->rad + $dt * $wheel->speed) % 360 );    #rotate the ball on the wheel

        $ball->x( $wheel->x + sin( $ball->rad * 3.14 / 180 ) * ( $wheel->size / 2 + 8 ));
        $ball->y( $wheel->y + cos( $ball->rad * 3.14 / 180 ) * ( $wheel->size / 2 + 8 ));

    }
    else {
        $ball->x( $ball->x + $ball->vx * $dt);
        $ball->y( $ball->y + $ball->vy * $dt);

        # Bounce our velocities components if we are going off the screen
        if ( ( $ball->x > ( $app->w - (13) ) && $ball->vx > 0 ) || ($ball->x < ( 0 + (13) ) && $ball->vx < 0) )
        {
            # if we bounce, we can go back to the previous wheel
            $ball->old_wheel( -1 );
            $ball->vx( $ball->vx * -1);
        }
        if ( ( $ball->y > ( $app->h - (13) ) && $ball->vy > 0) || ( $ball->y < ( 0 + (13) ) && $ball->vy < 0) )
        {
            # if we bounce, we can go back to the previous wheel
            $ball->old_wheel( -1 );
            $ball->vy( $ball->vy * -1 );
        }

   
        foreach ( 0 .. $#{$particles} ) {

            # don't collide with previous wheel
            next if $_ == $ball->old_wheel;

            warn 'mouse' if $DEBUG;
            my $p = @{$particles}[$_];

           # Check if our mouse rectangle collides with the particle's rectangle
            my $rad = ( $p->size / 2 ) + 10;
            if (   ( $ball->x < $p->x + $rad )
                && ( $ball->x > $p->x - $rad )
                && ( $ball->y < $p->y + $rad )
                && ( $ball->y > $p->y - $rad ) )
            {

                #warn 'iterating at wheel = ' . $ball->{wheel};

                #We got that sucker!!
                #Get rid of the particle for us
                $ball->n_wheel( $_ );

                # We are done no more particles left lets get outta here
                #return if $#{$particles} == -1;

            }
        }
    }

}

# Create a background surface once so we
# Can keep using it as many times as we need
sub init_bg_surf {
    my $app = shift;
    my $bg =
      SDL::Surface->new( SDL_SWSURFACE, $app->w, $app->h, 32, 0, 0, 0, 0 );

    SDL::Video::fill_rect( $bg, $app_rect,
        SDL::Video::map_RGB( $app->format, 60, 60, 60 ) );

    SDL::Video::display_format($bg);
    return $bg;
}

# Check if we are done this level
sub check_win {
    my $init_time = shift;
    if ( $particles_left <= 0 ) {
        my $secs_to_win = ( SDL::get_ticks() - $init_time / 1000 );
        my $str         = sprintf( "Level %d completed in : %2d millisecs !!!",
            $level, $secs_to_win );
        SDL::GFX::Primitives::string_color(
            $app,
            $app->w / 2 - 150,
            $app->h / 2 - 4,
            $str, 0x00FF00FF
        );

        $level++;
        SDL::Video::flip($app);
        SDL::delay(1000);
        return 0;

    }
    return 1;
}


# Release ball from wheel (if possible)
sub check_ball_release {

    # we can't release the ball if it isn't attached to a wheel
    return if $ball->n_wheel == -1;

    my $w = $particles->[ $ball->n_wheel ];

    if ( !$w->visited ) {
        # change wheel color so player knows it's touched
        $w->color( 0x111111FF );
        $w->surface( init_surface( $w->size, $w->color ) );

        $w->visited(1);
        $particles_left--;
    }

    # ball gets new speed
    $ball->vx( sin( $ball->rad * 3.14 / 180 ) * $w->speed * 1.2 );
    $ball->vy( cos( $ball->rad * 3.14 / 180 ) * $w->speed * 1.2 );

    $ball->old_wheel( $ball->n_wheel );
    $ball->n_wheel( -1 );
}

#Gets a random color for our particle
sub rand_color {
    my $r = rand( 0x100 - 0x44 ) + 0x44;
    my $b = rand( 0x100 - 0x44 ) + 0x44;
    my $g = rand( 0x100 - 0x44 ) + 0x44;

    return ( 0x000000FF | ( $r << 24 ) | ( $b << 16 ) | ($g) << 8 );
}

sub init_surface {
    my ($size, $color) = @_;

    #make a surface based on the size
    my $surface = SDL::Surface->new( SDL_SWSURFACE,
                                     $size + 15, $size + 15,
                                     32, 0, 0, 0, 255
                                   );

    SDL::Video::fill_rect(
        $surface,
        SDL::Rect->new( 0, 0, $size + 15, $size + 15 ),
        SDL::Video::map_RGB( $app->format, 60, 60, 60 )
    );

    #draw a circle on it with a random color
    SDL::GFX::Primitives::filled_circle_color(
            $surface,
            $size / 2,
            $size / 2,
            $size / 2 - 2,
            $color || rand_color(),
    );

    SDL::GFX::Primitives::aacircle_color( $surface, $size / 2, $size / 2,
        $size / 2 - 2, 0x000000FF );
    SDL::GFX::Primitives::aacircle_color( $surface, $size / 2, $size / 2,
        $size / 2 - 1, 0x000000FF );

    SDL::Video::display_format($surface);
    my $pixel = SDL::Color->new( 60, 60, 60 );
    SDL::Video::set_color_key( $surface, SDL_SRCCOLORKEY, $pixel );

    return $surface;
}


# The final update that is drawn to the screen
sub draw_to_screen {
    my ( $fps, $level ) = @_;

    #Blit the back ground surface to the window
    SDL::Video::blit_surface(
        $bg_surf, SDL::Rect->new( 0, 0, $bg_surf->w, $bg_surf->h ),
        $app,     SDL::Rect->new( 0, 0, $app->w,     $app->h )
    );

    # Draw out all our failures to hit the particles
    foreach ( 0 .. $#shots ) {
        warn 'show_draw' if $DEBUG;
        SDL::Video::fill_rect( $app, $shots[$_],
            SDL::Video::map_RGB( $app->format, 0, 0, 0 ) );
    }

    #make a string with the FPS and level
    my $pfps =
      sprintf( "FPS:%.2f Level:%2d Wheel:%2d, Wheel-speed:%.2f", $fps, $level, $ball->n_wheel, $particles->[$ball->n_wheel]->speed );

    #write our string to the window
    SDL::GFX::Primitives::string_color( $app, 3, 3, $pfps, 0x00FF00FF );

    #Draw each particle
    $_->draw($app) foreach ( @$particles );

    draw_ball();

    #Update the entire window
    #This is one frame!
    SDL::Video::flip($app);
}

sub draw_ball {

   my $wheel = $particles->[ $ball->n_wheel ];

    my $new_part_rect = SDL::Rect->new( 0, 0, 26, 26 );

    if($ball->n_wheel != -1) {
        # sin(rad) = opposite / hypo
        my $x2 = my $y2 = 0;
        my $xD = -1 ;my $yD = 1;
        $yD = -1 if $ball->rad < 270 && $ball->rad > 90;
        $xD = 1  if $ball->rad < 180 && $ball->rad > 0;
        $x2 = ($ball->x + 12 * $xD ) + (70 * sin ( $ball->rad * 3.14/180 ) );
        $y2 = ($ball->y + 12 * $yD ) + (70 * cos ( $ball->rad * 3.14/180 ) );
    
        SDL::GFX::Primitives::aaline_RGBA( $app, $ball->x,  $ball->y, $x2, $y2, 23, 244, 45, 244 );
    }

    #Blit the particles surface to the app in the right location
    SDL::Video::blit_surface(
        $ball->surface,
        $new_part_rect,
        $app,
        SDL::Rect->new(
            $ball->x - ( 26 / 2 ), $ball->y - ( 26 / 2 ),
            $app->w, $app->h
        )
    );
}

