package V2::Server::Controller::Booking;

use Moose;
use namespace::autoclean;
use Data::Dumper;
use DateTime;
use DateTime::Duration;
use DateTime::Span;
#Voodoo modules
use Date::ICal;
use Data::ICal;
use Data::ICal::DateTime; 
use Data::ICal::Entry::Event;

BEGIN { extends 'Catalyst::Controller::REST' }

=head1 NAME

V2::Server::Controller::Booking_P - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 begin
Begin is the first function executed when a request directed to /booking is made.
Some parameters must be saved in the stash, otherwise they are lost once the object
Catalyst::REST::Request is created (which overwrites the original $c->request).
=cut

sub begin : Private {
    my ( $self, $c ) = @_;
    $c->stash->{id_resource} = $c->request->query_parameters->{resource};
    $c->stash->{ical} = $c->request->query_parameters->{ical};
    $c->log->debug(Dumper($c->request->query_parameters));
    $c->stash->{format} = $c->request->headers->{"accept"}
        || 'application/json';
}

=head2 default
/booking is mapped to this function.
It redirects to default_GET, default_POST, etc depending on the http method used.
=cut

sub default : Local : ActionClass('REST') {
 my ( $self, $c ) = @_;
}

=head2 default_GET
There are 3 options:
  -Complete list of bookings (not very useful): /booking GET which redirects to the Private function
get_list
  -A booking: /booking/id GET which redirects to the Private function get_booking
  -A resource's agenda: /booking?resource=id GET which redirects to bookings_resource
=cut

sub default_GET {
  my ( $self, $c, $res, $id ) = @_;

  if ($id) {
        $c->detach( 'get_booking', [$id] );
    }else {
      if ($c->stash->{id_resource}) {
	$c->detach('bookings_resource', []);
      }else{	  
	  $c->detach( 'booking_list', [] );
      }
    }
}

=head2 get_booking
This function is not accessible through the url: /booking/get_booking/id but /booking/id hence the
Private type.

See default_GET for details.
=cut

sub get_booking : Private {
    my ( $self, $c, $id ) = @_;

    my $booking_aux = $c->model('DB::Booking')->find( { id => $id } );

    if ($booking_aux) {
        my @booking = $booking_aux->hash_booking;

        $c->stash->{content} = \@booking;
        $c->stash->{booking} = \@booking;
        $c->response->status(200);
        $c->stash->{template} = 'booking/get_booking.tt';

    }
    else {
        $c->stash->{template} = 'old_not_found.tt';
        $c->response->status(404);
    }
}

=head2 booking_list
Private function accessible through /booking GET 
It returns every booking of every resource. 
=cut

sub booking_list : Private {
    my ( $self, $c ) = @_;

    my @booking_aux = $c->model('DB::Booking')->all;
    my @booking;
    my @bookings;

    foreach (@booking_aux) {
        @booking = $_->hash_booking;
	$c->log->debug("Duration booking #".$_->id.": ".$_->duration);
        push( @bookings, @booking );
    }

    $c->stash->{content}  = \@bookings;
    $c->stash->{bookings} = \@bookings;
    my @events = $c->model('DB::Event')->all;
    $c->stash->{events} = \@events;
    my @resources = $c->model('DB::Resources')->all;
    $c->stash->{resources} = \@resources;
    $c->stash->{content}   = \@bookings;
    $c->stash->{bookings}  = \@bookings;
    $c->response->status(200);
    $c->stash->{template} = 'booking/get_list.tt';

}

=head2 bookings_resource
It returns the agenda of a resource.
$id has been got from $c->stash->{id_resource} as you can see in default_GET
=cut
sub bookings_resource :Private {
  my ($self, $c) = @_;
  
  my $id = $c->stash->{id_resource};
  my $ical = $c->stash->{ical};
  
  $c->log->debug("ID: ".$id);
  $c->log->debug("ICal: ".$ical);
  
  if ($ical){
    $c->detach('ical',[]);
  }
  
  my @booking_aux = $c->model('DB::Booking')->search( { id_resource =>
  $id });
  
  my @booking;
  my @bookings;
  
  # hash_booking is a function implemented in Schema/Result/Booking.pm it makes the booking easier
  # to handle
  
  foreach (@booking_aux) {
    @booking = $_->hash_booking;
    push( @bookings, @booking );
  }
  
  #Whatever is put inside $c->stash->{content} is encoded to JSON, if that's the view requested
  $c->stash->{content}  = \@bookings;
  #The HTML view uses $c->stash->{booking} because it makes clearer and more understandable the TT
  #templates
  $c->stash->{bookings} = \@bookings;
  #Events and Resources are passed to the HTML view in order to build the select menus
  my @events = $c->model('DB::Event')->all;
  $c->stash->{events} = \@events;    
  my @resources = $c->model('DB::Resources')->all;
  $c->stash->{resources} = \@resources;
  
  $c->response->status(200);
  $c->stash->{template} = 'booking/get_list.tt';
}

=head2 default_POST
/booking POST
This function creates a booking for a resource and associate it to an event.

After checking that the event and the resource actually exist, we proceed to insert the booking in
the table booking of the DB if, and only if, there isn't overlapping with another previously
existing booking.

Some of the check_[....] functions are reused by other modules, so I've put them together in the
controller Check. 

check_overlap is an special case, some may suggest that it should be placed in the
Schema/Booking.pm but by doing that the only thing that we achieve is an increase of code
complexity. $c for the win!
=cut

sub default_POST {
    my ( $self, $c ) = @_;
    my $req = $c->request;
    $c->log->debug( 'Mètode: ' . $req->method );
    $c->log->debug("El POST funciona");

    my $id_resource = $req->parameters->{id_resource};
    my $id_event    = $req->parameters->{id_event};
    
    my $dtstart     = $req->parameters->{dtstart};
    my $dtend       = $req->parameters->{dtend};
    my $duration;

#dtstart and dtend are parsed in case that some needed parameters to build the recurrence of the
#booking aren't provided
    $c->log->debug("Ara parsejarem dtsart");
    $dtstart = ParseDate($dtstart);
    $c->log->debug("Ara parsejarem dtend");
    $dtend = ParseDate($dtend);
    $duration = $dtend - $dtstart;

    my $freq   = $req->parameters->{freq} || "daily" ;
    my $interval    = $req->parameters->{interval} || 1;
    my $until       = $req->parameters->{until} || $req->parameters->{dtend};

    my $by_minute = $req->parameters->{by_minute} || $dtstart->minute;
    my $by_hour = $req->parameters->{by_hour} || $dtstart->hour;

#by_day may not be provided, so in order to build a proper ICal object, an array containing English
#day abbreviations is needed.
#    my @day_abbr = ('mo','tu','we','th','fr','sa','su');
    
    my $by_day = $req->parameters->{by_day} ||
"";#@day_abbr[$dtstart->day_of_week-1];
    my $by_month = $req->parameters->{by_month} || "";#$dtstart->month;
    my $by_day_month = $req->parameters->{by_day_month} || "";

    my $new_booking = $c->model('DB::Booking')->find_or_new();
    $c->stash->{id_event} = $id_event;
    $c->stash->{id_resource} = $id_resource;

#Do the resource and the event exist?
    $c->visit( '/check/check_booking', [ ] );    


    $new_booking->id_resource($id_resource);
    $new_booking->id_event($id_event);
    $new_booking->dtstart($dtstart);
    $new_booking->dtend($dtend);
#Duration is saved in minuntes in the DB in order to make it easier to deal with it when the server
#builds the JSON objects
#It sounds strange, but it works. Don't mess with the duration, the result can be weird.
    $new_booking->duration($duration->in_units("minutes"));
    $new_booking->frequency($freq);
    $new_booking->interval($interval);
    $new_booking->until($until);
    $new_booking->by_minute($by_minute);
    $new_booking->by_hour($by_hour);
    $new_booking->by_day($by_day);
    $new_booking->by_month($by_month);
    $new_booking->by_day_month($by_day_month);

    $c->stash->{new_booking}=$new_booking;

    $c->visit('/check/check_overlap',[]);
    my @message;
    if ( $c->stash->{booking_ok} == 1 ) {

        if ( $c->stash->{overlap} == 1 or $c->stash->{empty} == 1) {
	  if ($c->stash->{empty} == 1) {
	    @message
	    = { message => "Bad Request", };
	    $c->response->status(400);
	  }else{
	    @message
	    = { message => "Error: Overlap with another booking", };
	    $c->response->status(409);
	  }

            $c->stash->{content} = \@message;            
	    $c->stash->{error}    = "Error: Overlap with another booking or bad parameters";
            $c->stash->{template} = 'booking/get_list';
        }
        else {
            $new_booking->insert;

            my @booking = $new_booking->hash_booking;

            $c->stash->{content} = \@booking;
            $c->stash->{booking} = \@booking;
            $c->response->status(201);
            $c->stash->{template} = 'booking/get_booking.tt';

        }
    }
    else {
        my @message
            = { message => "Error: Check if the event or the resource exist",
            };
        $c->stash->{content} = \@message;
        $c->response->status(400);
        $c->stash->{error}
            = "Error: Check if the event or the resource exist";
        $c->stash->{template} = 'booking/get_list.tt';

    }
}

=head2
Same functionality than default_POST but updating an existing booking.
=cut

sub default_PUT {
    my ( $self, $c, $res, $id ) = @_;
    my $req = $c->request;
    $c->log->debug( 'Mètode: ' . $req->method );
    $c->log->debug("El PUT funciona");

    my $id_resource = $req->parameters->{id_resource};
    my $id_event    = $req->parameters->{id_event};
    
    my $dtstart     = $req->parameters->{dtstart};
    my $dtend       = $req->parameters->{dtend};
    my $duration;
    
    #dtstart and dtend are parsed in case that some needed parameters to build the recurrence of the
    #booking aren't provided
    $c->log->debug("Ara parsejarem dtsart");
    $dtstart = ParseDate($dtstart);
    $c->log->debug("Ara parsejarem dtend");
    $dtend = ParseDate($dtend);
    $duration = $dtend - $dtstart;
    
    my $freq   = $req->parameters->{freq} || "daily" ;
    my $interval    = $req->parameters->{interval} || 1;
    my $until       = $req->parameters->{until} || $req->parameters->{dtend};
    
    my $by_minute = $req->parameters->{by_minute} || $dtstart->minute;
    my $by_hour = $req->parameters->{by_hour} || $dtstart->hour;
    
    #by_day may not be provided, so in order to build a proper ICal object, an array containing
    #English day abbreviations is needed.
    my @day_abbr = ('mo','tu','we','th','fr','sa','su');
    
    my $by_day = $req->parameters->{by_day} ||
    @day_abbr[$dtstart->day_of_week-1];
    my $by_month = $req->parameters->{by_month} || $dtstart->month;
    my $by_day_month = $req->parameters->{by_day_month} || "";
    
    my $booking = $c->model('DB::Booking')->find({id => $id});
    $c->stash->{id_event} = $id_event;
    $c->stash->{id_resource} = $id_resource;
    
    #Do the resource and the event exist?
    $c->visit( '/check/check_booking', [ ] );    
    
    
    $booking->id_resource($id_resource);
    $booking->id_event($id_event);
    $booking->dtstart($dtstart);
    $booking->dtend($dtend);
    #Duration is saved in minuntes in the DB in order to make it easier to deal with it when the
    #server builds the JSON objects
    #It sounds strange, but it works. Don't mess with the duration, the result can be weird.
    $booking->duration($duration->in_units("minutes"));
    $booking->frequency($freq);
    $booking->interval($interval);
    $booking->until($until);
    $booking->by_minute($by_minute);
    $booking->by_hour($by_hour);
    $booking->by_day($by_day);
    $booking->by_month($by_month);
    $booking->by_day_month($by_day_month);
    
    #we are reusing /check/check_overlap that's why $booking is saved in $c->stash->{new_booking}
    #For the same reason we put to true $c->stash->{PUT} so we'll be able to amply the convenient 
    #restrictions to the search query (see check module for details)
    $c->stash->{new_booking}=$booking;
    $c->stash->{PUT} = 1;
    $c->visit('/check/check_overlap',[]);
    
    if ( $c->stash->{booking_ok} == 1 ) {
      
      if ( $c->stash->{overlap} == 1 ) {
	my @message
	= { message => "Error: Overlap with another booking", };
	$c->stash->{content} = \@message;
	$c->response->status(409);
	$c->stash->{error}    = "Error: Overlap with another booking";
	$c->stash->{template} = 'booking/get_list';
	}
	else {
	  $booking->update;
	  
	  my @booking = $booking->hash_booking;
	  
	  $c->stash->{content} = \@booking;
	  $c->stash->{booking} = \@booking;
	  $c->response->status(201);
	  $c->stash->{template} = 'booking/get_booking.tt';
	  
	}
      }
      else {
	my @message = { 
	  message => "Error: Check if the event or the resource exist",
	};
	$c->stash->{content} = \@message;
	$c->response->status(400);
	$c->stash->{error}
	= "Error: Check if the event or the resource exist";
	$c->stash->{template} = 'booking/get_list.tt';
	
      }
}

sub default_DELETE {
    my ( $self, $c, $res, $id ) = @_;
    my $req = $c->request;

    $c->log->debug( 'Mètode: ' . $req->method );
    $c->log->debug("El DELETE funciona");

    my $booking_aux = $c->model('DB::Booking')->find( { id => $id } );

    if ($booking_aux) {
        $booking_aux->delete;
	my @message = { message => "Booking succesfully deleted",
    };
	$c->stash->{content} = \@message;
        $c->stash->{template} = 'booking/delete_ok.tt';
        $c->response->status(200);
    }
    else {
        $c->stash->{template} = 'not_found.tt';
        $c->response->status(404);
    }
}

sub ParseDate {
    my ($date_str) = @_;

    my ( $day, $hour ) = split( /T/, $date_str );

    my ( $year,  $month, $nday ) = split( /-/, $day );
    my ( $nhour, $min)  = split( /:/, $hour );

    my $date = DateTime->new(
        year   => $year,
        month  => $month,
        day    => $nday,
        hour   => $nhour,
        minute => $min,
    );

    return $date;
}

=head2
The last function executed before responding the request.
Because we saved format in $c->stash->{format} it allow us to choose between the available views.
=cut

sub end : Private {
    my ( $self, $c ) = @_;

    if ($c->stash->{ical}){
      
    }else{
      if ( $c->stash->{format} ne "application/json" ) {
	$c->forward( $c->view('HTML') );
      }
      else {
	$c->forward( $c->view('JSON') );
      }
    }
}

sub ical : Private {
  my ($self,$c) = @_;
  
  my $filename = "agenda_resource_".$c->stash->{id_resource}.".ics";
  
  my $calendar = Data::ICal->new();
  
  $c->log->debug("Volem l'agenda del recurs ".$c->stash->{id_resource}." en format ICal");
  
  my @agenda_aux = $c->model('DB::Booking')->search({id_resource =>
$c->stash->{id_resource}})->search({until=>{'>'=> DateTime->now }});

  my @genda;
  
  foreach (@agenda_aux) {
    push (@genda,$_->hash_booking);
  }

  $c->log->debug("Hi ha ".@genda." que compleixen els criteris de cerca");
  #$c->log->debug(Dumper(@genda));
  
  my $s_aux;
  my $e_aux;
  my $u_aux;
  my $set_aux;
  my @byday; my @bymonth; my @bymonthday;
  
  foreach (@genda) {
    my $vevent = Data::ICal::Entry::Event->new();
    $s_aux = ParseDate($_->{dtstart});
    $e_aux = ParseDate($_->{dtend});
    $u_aux = ParseDate($_->{until});
    
    @byday = split(',',$_->{by_day});
    @bymonth = split(',',$_->{by_month});
    @bymonthday = split(',',$_->{by_day_month});
    
    $set_aux = DateTime::Event::ICal->recur(
      dtstart => $s_aux,
      until => $u_aux,
      freq =>    $_->{frequency},
      interval => $_->{interval},
      byminute => $_->{by_minute},
      byhour => $_->{by_hour},
      byday => \@byday,
      bymonth => \@bymonth,
      bymonthday => \@bymonthday
    );
    
   # $c->log->debug(Dumper($set_aux));
    #$c->log->debug("Abans de l'split: ".Dumper($set_aux->{as_ical}->[1]));
    my ($res,$rrule) = split(':',Dumper($set_aux->{as_ical}->[1]));
    ($rrule,$res) = split('\'',$rrule);
    #$c->log->debug("RRULE: ".$rrule);
    
    $vevent->add_properties(
      uid => $_->{id},
      summary => "Booking #".$_->{id},
      dtstart => Date::ICal->new(
	year => $s_aux->year,
	month => $s_aux->month,
	day => $s_aux->day,
	hour => $s_aux->hour,
	minute => $s_aux->minute,
      )->ical,
      dtend => Date::ICal->new(
	year => $e_aux->year,
	month => $e_aux->month,
	day => $e_aux->day,
	hour => $e_aux->hour,
	minute => $e_aux->minute,
      )->ical,
      duration => $_->{duration},
      rrule => $rrule
     
    );
    $calendar->add_entry($vevent);
    #$c->log->debug("ICal booking #".$_->{id});

  }
  
  $c->stash->{content} = \@genda;
  $c->res->content_type("text/calendar");
  #$c->log->debug("Fitxer: ".Dumper($calendar));
  $c->res->header(
    'Content-Disposition' => qq(inline; filename=$filename) );
  $c->res->output($calendar->as_string);
  
}

=head1 AUTHOR

Jordi Amorós Andreu,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
