package Smeagol::Shell;

use strict;
use warnings;

use Data::Dumper;
use Smeagol::Client;
use Smeagol::Server;
use Smeagol::DataStore;

use base qw(Term::Shell);
our $pid;
our $client;
our $idResource;

sub init {
  my $self = shift;
}

####CONNECTA
sub run_connecta {
  my $self = shift;
  my ($server) = @_;
  $server = "http://abydos.ac.upc.edu:8000" if (!defined $server);
  $client = Smeagol::Client->new($server);
  print "Connexió creada amb $server correctament!\n" if (ref $client eq 'Smeagol::Client');
  print "No s'ha pogut establir connexió amb $server!\n" if (ref $client ne 'Smeagol::Client');
}
sub smry_connecta { "Estableix connexió amb un servidor smeagol" }
sub help_connecta { "Cal introduir l'adreça del servidor, p.e. connecta http://localhost:8000 .\nSi no s'introdueix cap adreça es posa per defecte la del servidor de proves http://abydos.ac.upc.edu:8000\n"; }

####LISTAR RECURSOS
sub run_llista_recursos{
  my $self = shift;
  if(defined $client){
    my @res = $client->listResources();
    foreach(@res){
      print _idResource($_)."\n";
    }
  }else{
    print "ERROR: No es poden llistar els recursos, no hi ha connexió amb cap servidor smeagol\n";
  }
}

sub smry_llista_recursos { "Selecciona un recurs d'entre tots els existents. Aquest serà escollit per realitzar accions relacionades amb ell" }
sub help_llista_recursos { "Abans de poder llistar els recursos, cal que s'hagi connectat a un servidor smeagol previament (veure comanda connecta)\n"; }
sub comp_llista_recursos {
  my $self = shift;
}

####CREA RECURS
sub run_crea_recurs{
  my $self = shift;
  my ($desc) = @_;
  if(defined $client){
    if(!defined $desc){
      print "ERROR: Cal incloure una descripcio\n";
    }else{
      my $res = $client->createResource($desc);
	  if(defined $res){
        print "Recurs creat correctament! Dades del recurs:\n";
        print "Identificador: ". _idResource($res)."\n";
        print "Descripció   : $desc \n";
	  }else{
        print "ERROR: El recurs no s'ha pogut crear correctament\n";
	  }
    }
  }else{
    print "ERROR: No es pot crear un recurs, no hi ha connexió amb cap servidor smeagol\n";
  }
}

sub smry_crea_recurs { "Crea un recurs senzill amb una descripció" }
sub help_crea_recurs { "Abans de poder crear un recurs, cal que s'hagi connectat a un servidor smeagol previament (veure comanda connecta)\nLa descripció és obligatoria\n"; }
sub comp_crea_recurs {
  my $self = shift;
}

####TRIAR RECURS
sub run_tria_recurs{
  my $self = shift;
  my ($id) = @_;
  if(defined $client){
    if(!defined $id){
      print "ERROR: Cal introduir un identificador d'un recurs\n";
    }else{
      my $res = $client->getResource($id);
      if(!defined $res){
        print "ERROR: Identificador incorrecte. Recurs amb identificador $id no seleccionat\n";
        if(defined $idResource){
          print "       De moment queda triat el recurs $idResource\n"
        }else{
          print "       No hi ha cap recurs triat de moment\n"
        }
      }else{
        $idResource = $id;
        print "Recurs $idResource triat correctament\n";
      }
    }
  }else{
    print "ERROR: No es pot triar un recurs, no hi ha connexió amb cap servidor smeagol\n";
  }
}

sub smry_tria_recurs { "Selecciona un recurs d'entre tots els existents. Aquest serà escollit per realitzar accions relacionades amb ell" }
sub help_tria_recurs { "()\n"; }
sub comp_tria_recurs { my $self = shift;}

####CONSULTA RECURS
sub run_mostra_recurs{
  my $self = shift;
  if(!defined $idResource){
    print "ERROR: No hi ha recurs triat.\n";
  }else{
    my $res = $client->getResource($idResource);
    my @tags = $client->listTags($idResource);
    print "Dades del recurs $idResource:\nDescripcio: $res->{description}\nTags      : ";
    foreach(@tags){
      my @ids = _idResourceTag($_);
	  print $ids[1]."  ";
    }
	print "\n";
  }
}

sub smry_mostra_recurs { "Mostra les dades del recurs escollit" }
sub help_mostra_recurs { "Abans de poder mostrar un recurs, cal que aquest hagi estat triat previament (amb la comanda tria_recurs \"identificador\")\n"; }
sub comp_mostra_recurs { my $self = shift;}

####ESBORRAR RECURS
#Al'hora d'esborrar s'ha de posar $idResource=undef
sub run_esborra_recurs{
  my $self = shift;
  if(!defined $idResource){
    print "ERROR: No hi ha recurs triat.\n";
  }else{
    my $res = $client->delResource($idResource);
    if(!defined $res){
	    print "ERROR: No s'ha esborrat cap recurs\n";
    }else{
	  print "Recurs $idResource esborrat correctament!\n";
      $idResource = undef;
	}
  }
}

sub smry_esborra_recurs { "Esborra un recurs" }
sub help_esborra_recurs { "Abans de poder esborrar un recurs, cal que aquest hagi estat triat previament (amb la comanda tria_recurs \"identificador\")\n"; }
sub comp_esborra_recurs {
  my $self = shift;
}

####AFEGIR ETIQUETA
sub run_afegeix_etiqueta{
  my $self = shift;
  my ($tag) = @_;
  if(!defined $idResource){
    print "ERROR: No hi ha recurs triat.\n";
  }elsif($tag){
    my $res = $client->createTag($idResource, $tag);
    if(defined $res){
	  my @ids = _idResourceTag($res);
      print "Etiqueta ".$ids[1]." afegida al recurs ".$ids[0]." correctament!\n";
	}else{
      print "ERROR: No s'ha pogut afegir correctament\n";
	}
  }else{
    print "ERROR: No hi ha cap etiqueta introduïda.\n";
  }
}
sub smry_afegeix_etiqueta { "Afegeix una etiqueta pel recurs escollit" }
sub help_afegeix_etiqueta { "Abans de poder afegir una etiqueta a un recurs, cal que aquest hagi estat triat previament (veure comanda tria_recurs \"identificador\"). Una etiqueta ha de tenir entre 2 i 60 caràcters i només pot contenir lletres, números, '.', ':', '_' i '-' \n"; }
sub comp_afegeix_etiqueta { my $self = shift;}

####ESBORRAR ETIQUETA
sub run_esborra_etiqueta{
  my $self = shift;
  my ($tag) = @_;
  if(!defined $idResource){
    print "ERROR: No hi ha recurs triat.\n";
  }elsif($tag){
    my $res = $client->delTag($idResource, $tag);
    if(defined $res){
      print "Etiqueta $res esborrada del recurs $idResource correctament!\n";
	}else{
      print "ERROR: No s'ha pogut esborrar l'etiqueta $tag correctament\n";
	}
  }else{
    print "ERROR: No hi ha cap etiqueta introduïda.\n";
  }
}



sub smry_esborra_etiqueta { "Esborra una etiqueta pel recurs escollit" }
sub help_esborra_etiqueta { "Abans de poder esborrar una etiqueta a un recurs, cal que aquest hagi estat triat previament (veure comanda tria_recurs \"identificador\")\n"; }
sub comp_esborra_etiqueta { my $self = shift;}

####ALIAS
sub run_surt{
  my $self = shift;
  $self->run_exit(); 
}
sub smry_surt { "Surt del shell" }
sub help_surt { "\n"; }

sub run_ajuda{
  my $self = shift; 
  $self->run_help();
}
sub smry_ajuda { "Mostra ajuda" }
sub help_ajuda { " \n"; }


####COMANDA DESCONEGUDA
sub msg_unknown_cmd {
  my $self = shift;  
  my ($cmd) = @_;
  print "Comanda '$cmd' desconeguda; escriu 'help' per obtenir ajuda.\n";
}


####Metodes interns
sub _idResource {
    my ($url) = shift;

    if ( $url =~ /\/resource\/(\w+)/ ) {
        return $1;
    }
    else {
        return;
    }
}

sub _idResourceBooking {
    my ($url) = shift;

    if ( $url =~ /resource\/(\d+)\/booking\/(\d+)/ ) {
        return ( $1, $2 );
    }
    else {
        return;
    }
}

sub _idResourceTag {
    my ($url) = shift;

    if ( $url =~ /resource\/(\d+)\/tag\/([\w.:_\-]+)/ ) {
        return ( $1, $2 );
    }
    else {
        return;
    }
}

1;