package V2::Server::Controller::Booking_S;

use Moose;
use namespace::autoclean;
use Data::Dumper;
use JSON;
use DateTime::Span; 

BEGIN { extends 'Catalyst::Controller::REST' }

=head1 NAME

V2::Server::Controller::Booking_P - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index

=cut

sub default : Local : ActionClass('REST') {
}

sub default_GET  {
  my ( $self, $c, $res, $id ) = @_;
  my $j = JSON->new;
  
  if ($id) {
    my $booking_aux = $c->model('DB::Booking')->find({id=>$id});

    if ($booking_aux){
	my @booking = {
	  id=> $booking_aux->id,
	  id_resource=> $booking_aux->id_resource->id,
	  id_event=> $booking_aux->id_event->id,
	  starts=> $booking_aux->starts->iso8601(),
	  ends=> $booking_aux->ends->iso8601(),
	};

	my $jbooking = $j->encode(\@booking);
	$c->log->debug($jbooking);  

	$c->stash->{booking}=$jbooking;
	$c->stash->{template}='booking_s/get_booking.tt';
	$c->forward( $c->view('TT') );
	
    } else {
	$c->stash->{template}='not_found.tt';
	$c->forward( $c->view('TT') );

    }   
   
  }else{
    my @booking_aux = $c->model('DB::Booking')->all;
    my @booking;
    my @bookings;

    foreach (@booking_aux) {
          @booking = {
	    id=> $_->id,
	    id_resource=> $_->id_resource->id,
	    id_event=> $_->id_event->id,
	    starts=> $_->starts->iso8601(),
	    ends=> $_->ends->iso8601(),
	  };

	  push (@bookings, @booking);
    }
    
    my $jbookings = $j->encode(\@bookings);
    $c->log->debug($jbookings);  

    $c->stash->{bookings}=$jbookings;
    $c->stash->{template}='booking_s/get_list.tt';
    $c->forward( $c->view('TT') );
  }
  
}

sub default_POST {
  my ( $self, $c) = @_;
  my $req=$c->request;
  $c->log->debug('Mètode: '.$req->method);
  $c->log->debug ("El POST funciona");
  my $j = JSON->new;

  my $id_resource=$req->parameters->{id_resource};
  my $id_event=$req->parameters->{id_event};
  my $starts=$req->parameters->{starts};
  my $ends=$req->parameters->{ends};

  my $new_booking = $c->model('DB::Booking')->find_or_new();

  $new_booking->id_resource($id_resource);
  $new_booking->id_event($id_resource);
  $new_booking->starts($starts);
  $new_booking->ends($ends);  
  
  my @old_bookings = $c->model('DB::Booking')->search({id_resource=>$id_resource}); #Recuperem les reserves que utilitzen el recurs
  
  my $current_set = DateTime::Span->from_datetimes(start=>$new_booking->starts , end=>$new_booking->ends);
 
  my $old_booking_set;
  my $overlap_aux;
  my $overlap = 0;
  
  $c->log->debug ("# de reserves: ".@old_bookings);
  
  foreach (@old_bookings){
    $c->log->debug("Start: ".$_->starts);
    $c->log->debug("End: ".$_->ends);
    
    $old_booking_set = DateTime::Span->from_datetimes((start=>$_->starts , end=>$_->ends));
  
    if ($old_booking_set->intersects($current_set)){
      $overlap = 1;
      last;
    }
  
  }
  
  if ($overlap) {      
    $c-> stash-> {template} = 'fail.tt';
    $c->forward( $c->view('TT') );
  }else {
    $new_booking->insert;

    my @booking = {
      id=> $new_booking->id,
      id_resource=> $new_booking->id_resource->id,
      id_event=> $new_booking->id_event->id,
      starts=> $new_booking->starts->iso8601(),
      ends=> $new_booking->ends->iso8601(),
    };

    my $jbooking = $j->encode(\@booking);
    $c->log->debug($jbooking);  

    $c->stash->{booking}=$jbooking;
    $c->stash->{template}='booking_s/get_booking.tt';
    $c->forward( $c->view('TT') );
  
  }    
}

sub default_PUT {
  my ( $self, $c, $res, $id) = @_;
  my $req=$c->request;
  $c->log->debug('Mètode: '.$req->method);
  $c->log->debug ("El PUT funciona");
  my $j = JSON->new;

  my $id_resource=$req->parameters->{id_resource};
  my $id_event=$req->parameters->{id_event};
  my $starts=$req->parameters->{starts};
  my $ends=$req->parameters->{ends};

  my $booking = $c->model('DB::Booking')->find({id=>$id});

  $booking->id_resource($id_resource);
  $booking->id_event($id_event);
  $booking->starts($starts);
  $booking->ends($ends);
  
  my @old_bookings = $c->model('DB::Booking')->search({id_resource=>$id_resource}); #Recuperem les reserves que utilitzen el recurs
  
  my $current_set = DateTime::Span->from_datetimes(start=>$req->parameters->{starts} , end=>$req->parameters->{ends});
 
  my $old_booking_set;
  my $overlap_aux;
  my $overlap = 0;
  
  $c->log->debug ("# de reserves: ".@old_bookings);
  
  foreach (@old_bookings){
    $c->log->debug("Start: ".$_->starts);
    $c->log->debug("End: ".$_->ends);
    
    $old_booking_set = DateTime::Span->from_datetimes((start=>$_->starts , end=>$_->ends));
  
    if ($old_booking_set->intersects($current_set)){
      $overlap = 1;
      last;
    }
  
  }
  
  if ($overlap){
    $c-> stash-> {template} = 'fail.tt';
    $c->forward( $c->view('TT') );
  }else {
      $booking->update;

      my @booking = {
	id=> $booking->id,
	id_resource=> $booking->id_resource->id,
	id_event=> $booking->id_event->id,
	starts=> $booking->starts->iso8601(),
	ends=> $booking->ends->iso8601(),
      };

      my $jbooking = $j->encode(\@booking);
      $c->log->debug($jbooking);  

      $c->stash->{booking}=$jbooking;
      $c->stash->{template}='booking_s/get_booking.tt';
      $c->forward( $c->view('TT') );      
      }  

}

sub default_DELETE {
      my ($self, $c, $res, $id) = @_;
      my $req=$c->request;
      
      $c->log->debug('Mètode: '.$req->method);	
      $c->log->debug ("El DELETE funciona");
      
      my $booking_aux = $c->model('DB::Booking')->find({id=>$id});
      
      if ($booking_aux){
	    $booking_aux-> delete;
	    $c-> stash-> {template} = 'booking_s/delete_ok.tt';
	    $c->forward( $c->view('TT') );
      }else{
	    $c-> stash-> {template} = 'not_found.tt';
	    $c->forward( $c->view('TT') );
      }
}


=head1 AUTHOR

Jordi Amorós Andreu,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
