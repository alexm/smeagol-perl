package V2::Server::Controller::Resource;

use Moose;
use namespace::autoclean;
use Data::Dumper;

BEGIN { extends 'Catalyst::Controller::REST' }

=head1 NAME

V2::CatalystREST::Controller::resource - Catalyst Controller

=head1 name

Catalyst Controller.

=head1 METHODS

=cut

=head2 default

=cut

sub begin : Private {
    my ( $self, $c ) = @_;

    $c->stash->{format} = $c->request->headers->{"accept"}
        || 'application/json';
}

sub default : Path : ActionClass('REST') {
}

sub default_GET {
    my ( $self, $c, $id ) = @_;

    if ($id) {
        $c->forward( 'get_resource', [$id] );
    }
    else {
        $c->forward( 'resource_list', [] );
    }
}

sub get_resource : Private {
    my ( $self, $c, $id ) = @_;
    my $resource = $c->model('DB::Resources')->find( { id => $id } );

    if ( !$resource ) {

        my @message
            = { message => "We can't find what you are looking for." };
        $c->stash->{content}  = \@message;
        $c->stash->{template} = 'old_not_found.tt';
        $c->response->status(404);
    }
    else {
        my @resource;
        push( @resource, $resource->get_resources );
        $c->stash->{resource} = \@resource;
        $c->stash->{content}  = \@resource;
        $c->response->status(200);
        $c->stash->{template} = 'resource/get_resource.tt';
    }
}

sub resource_list : Private {
    my ( $self, $c ) = @_;
    my @resources;
    my @res_aux = $c->model('DB::Resources')->all;

    foreach (@res_aux) {
        push( @resources, $_->get_resources );

    }

    $c->stash->{resources} = \@resources;
    $c->stash->{content}   = \@resources;
    $c->response->status(200);
    $c->stash->{template} = 'resource/get_list.tt';
}

sub default_POST {
    my ( $self, $c, $id ) = @_;
    my $req = $c->request;

    $c->log->debug( 'Mètode: ' . $req->method );
    $c->log->debug("El POST funciona");
    $c->log->debug( Dumper( $req->parameters ) );

    my $descr = $req->parameters->{description};
    my $info  = $req->parameters->{info};

    my $tags_aux = $req->parameters->{tags};
    my @tags = split( /,/, $tags_aux );

    $c->visit( '/check/check_resource', [ $info, $descr ] );

# If all is correct $c->stash->{event_ok} should be 1, otherwise it will be 0.

    if ( $c->stash->{resource_ok} ) {

        my $new_resource = $c->model('DB::Resources')->find_or_new();

        $new_resource->description($descr);
        $new_resource->info($info);
        $new_resource->insert;

        $c->log->debug( "La id del nou recurs és: " . $new_resource->id );

#Buscarem si els tags ja existeixen, en cas de no existir els crearem
#Cal omplir DB::ResourceTag per a establir la relació entre els tags i els recursos

        my $TagID;

        foreach (@tags) {
            $TagID = $c->model('DB::Tag')->find( { id => $_ } );

            if ($TagID) {
                $c->log->debug( 'Llista id\'s tag: ' . $TagID->id );

         #Si el tag existeix, fem constar a ResourceTag la relació recurs-tag
                my $ResTag = $c->model('DB::ResourceTag')->find_or_new();
                $ResTag->resource_id( $new_resource->id );
                $ResTag->tag_id( $TagID->id );
                $ResTag->insert;

            }
            else {

                #Si el tag no existeix, el creem i repetim com a dalt
                my $new_tag = $c->model('DB::Tag')->find_or_new();

                $new_tag->id($_);
                $new_tag->insert;

                $c->log->debug( 'Nou tag: ' . $new_tag->id );

                my $ResTag = $c->model('DB::ResourceTag')->find_or_new();
                $ResTag->resource_id( $new_resource->id );
                $ResTag->tag_id( $new_tag->id );
                $ResTag->insert;
            }
        }

#Un cop tenim el tema dels tags aclarit, muntem el json amb les dades del recurs
        my @resource = {
            id          => $new_resource->id,
            description => $new_resource->description,
            info        => $new_resource->info,
            tags        => $new_resource->tag_list,
        };

        $c->stash->{resource} = \@resource;
        $c->stash->{content}  = \@resource;
        $c->response->status(201);
        $c->response->content_type('text/html');
        $c->stash->{template} = 'resource/get_resource.tt';
    }
    else {
        my @message = { message =>
                "Error: Check the info and description of the resource", };
        $c->stash->{content} = \@message;
        $c->response->status(400);
        $c->stash->{error}
            = "Error: Check the info and description of the resource";
	$c->response->content_type('text/html');
	$c->stash->{template} = 'resource/get_list.tt';
    }
}

sub default_PUT {
    my ( $self, $c, $id ) = @_;
    my $req = $c->request;
    $c->log->debug( 'Mètode: ' . $req->method );
    $c->log->debug("El PUT funciona");

    my $descr = $req->parameters->{description}
        || $req->{headers}->{description};

    $c->log->debug( "Description: " . $descr );

    my $tags_aux = $req->parameters->{tags} || $req->{headers}->{tags};
    my $info     = $req->parameters->{info} || $req->{headers}->{info};
    my @tags = split( /,/, $tags_aux );

    my $resource = $c->model('DB::Resources')->find( { id => $id } );

    if ($resource) {
        $c->visit( '/check/check_resource', [ $info, $descr ] );

# If all is correct $c->stash->{event_ok} should be 1, otherwise it will be 0.
        if ( $c->stash->{resource_ok} ) {
            $resource->description($descr);
            $resource->info($info);
            $resource->update;

            my $TagID;

            my @old_tags = $c->model('DB::ResourceTag')
                ->search( { resource_id => $id } );

            foreach (@old_tags) {
                $c->log->debug( 'Tags vells: ' . $_->tag_id );
                $_->delete;
            }

            foreach (@tags) {
                $TagID = $c->model('DB::Tag')->find( { id => $_ } );

                if ($TagID) {

         #Si el tag existeix, fem constar a ResourceTag la relació recurs-tag
                    my $ResTag = $c->model('DB::ResourceTag')->find_or_new();
                    $ResTag->resource_id( $resource->id );
                    $ResTag->tag_id( $TagID->id );
                    $ResTag->insert;

                }
                else {

                    #Si el tag no existeix, el creem i repetim com a dalt
                    my $new_tag = $c->model('DB::Tag')->find_or_new();

                    $new_tag->id($_);
                    $new_tag->insert;

                    $c->log->debug( 'Nou tag: ' . $new_tag->id );

                    my $ResTag = $c->model('DB::ResourceTag')->find_or_new();
                    $ResTag->resource_id( $resource->id );
                    $ResTag->tag_id( $new_tag->id );
                    $ResTag->insert;
                }

            }

            my @resource = {
                id          => $resource->id,
                description => $resource->description,
                info        => $resource->info,
                tags        => $resource->tag_list,
            };

            $c->stash->{resource} = \@resource;
            $c->stash->{content}  = \@resource;
            $c->response->status(200);
        }
        else {
            my @message
                = { message =>
                    "Error: Check the info and description of the resource",
                };
            $c->stash->{content} = \@message;
            $c->response->status(400);
            $c->stash->{error}
                = "Error: Check the info and description of the resource";
	    $c->response->content_type('text/html');
            $c->stash->{template} = 'resource/get_list';
        }
    }
    else {
        my @message
            = { message => "We can't find what you are looking for." };
        $c->stash->{content}  = \@message;
        $c->stash->{template} = 'old_not_found.tt';
        $c->response->content_type('text/html');
        $c->response->status(404);
    }

}

sub default_DELETE {
    my ( $self, $c, $id ) = @_;
    my $req = $c->request;

    $c->log->debug( 'Mètode: ' . $req->method );
    $c->log->debug( "ID: " . $id );
    $c->log->debug("El DELETE funciona");

    my $resource_aux = $c->model('DB::Resources')->find( { id => $id } );

    if ($resource_aux) {
        $resource_aux->delete;

        #$c->stash->{template} = 'resource/delete_ok.tt';
        #$c->response->status(200);
        #$c->forward( $c->view('HTML') );
        $c->go("/resource/resource_list");
    }
    else {

        my @message
            = { message => "We can't find what you are looking for." };
        $c->stash->{content}  = \@message;
        $c->stash->{template} = 'old_not_found.tt';
        $c->response->status(404);
    }

}

sub end : Private {
    my ( $self, $c ) = @_;

    if ( $c->stash->{format} ne "application/json" ) {
        $c->forward( $c->view('HTML') );
    }
    else {
        $c->forward( $c->view('JSON') );
    }
}

=head1 AUTHOR

Jordi Amorós Andreu

=cut

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
