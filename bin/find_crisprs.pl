#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;

use LIMS2::REST::Client;
use YAML::Any qw( LoadFile DumpFile );
use Try::Tiny;
use Log::Log4perl qw( :easy );
use Data::Dumper;
use Path::Class;
use Bio::Perl qw( revcom );

Log::Log4perl->easy_init( $DEBUG );

my ( $species, @ids, $fq_file, $crispr_file, $pair_file );
my $include_completed = 0;
my $flank = 200;
GetOptions(
    "help"               => sub { pod2usage( 1 ) },
    "man"                => sub { pod2usage( 2 ) },
    "species=s"          => sub { my ( $name, $val ) = @_; $species = ucfirst( lc $val ); },
    "ids=s{,}"           => \@ids,
    "fq-file=s"          => sub { my ( $name, $val ) = @_; $fq_file = file( $val ); },
    "crispr-yaml-file=s" => \$crispr_file,
    "flank"              => \$flank,
    "include-completed!" => \$include_completed,
) or pod2usage( 2 );

die pod2usage( 2 ) unless $species and @ids and ($fq_file or $crispr_file);


#check which kind of ids we got
my @exon_ids = grep { /^ENS(MUS)?E\d+$/ } @ids;
my @crispr_ids = grep { /^\d+$/ } @ids;
die "You must provide exons OR crisprs ids, not both." if @exon_ids and @crispr_ids;

my $client = LIMS2::REST::Client->new_with_config(
    configfile => $ENV{WGE_REST_CLIENT_CONFIG}
);

#ugly duplication. refactor
my $all_crisprs;
if ( @exon_ids ) {
    WARN "Some exon ids were invalid" unless @exon_ids == @ids;
    DEBUG "Fetching crisprs for exon ids: " . join( ", ", @exon_ids );
    DEBUG "Exons will be flanked by $flank bases" if $flank;
    $all_crisprs = $client->GET(
        'crisprs_by_exon', 
        { exons => \@exon_ids, species => $species, flank => $flank }
    );
}
elsif ( @crispr_ids ) {
    WARN "Some crispr ids were invalid" unless @crispr_ids == @ids;
    DEBUG "Fetching crisprs for exon ids: " . join( ", ", @crispr_ids );
    $all_crisprs = $client->GET(
        'crispr', 
        { id => \@crispr_ids, species => $species, return_array => 1 }
    );
}
else {
    die "Couldn't find any crispr ids or exon ids in: " . join ", ", @ids;
}

die "Couldn't find any crisprs!" unless @{ $all_crisprs };

my $fq_fh = $fq_file->openw or die "Can't open $fq_file: $!";
my $total_crisprs = 0;
my %crispr_data;
for my $crispr ( @{ $all_crisprs } ) {
    unless ( $include_completed ) {
        if ( defined $crispr->{off_target_summary} ) {
            DEBUG $crispr->{id} . " already has off target data, skipping.";
            next 
        }
    }

    $total_crisprs++;

    $crispr->{ensembl_exon_id} ||= 'ENSE000'; #if there's no exon id use this placeholder
    #create the empty hash to conform to how we used to do crisprs
    $crispr_data{ $crispr->{ensembl_exon_id} }->{ $crispr->{id} } = {};

    #write the fq lines
    my $orientation = ( $crispr->{pam_right} ) ? "B" : "A";

    say $fq_fh ">" . $crispr->{ensembl_exon_id} . "_" . $crispr->{id} . $orientation;
    #we always store crisprs as pam right in the fq file.
    say $fq_fh ( $crispr->{pam_right} ) ? $crispr->{seq} : revcom( $crispr->{seq} )->seq;
}

DEBUG "Total number of crisprs found: " . scalar( @{ $all_crisprs } );
DEBUG "Total valid crisprs:" . $total_crisprs;

unless ( $total_crisprs ) {
    die "Couldn't find any valid crisprs! Try re-running with --include-completed";
}
#show the number of crisprs for each exon
DEBUG join "\n", map { $_ . ": " . scalar( keys %{ $crispr_data{$_} } ) } keys %crispr_data;

DumpFile( $crispr_file, \%crispr_data );

1;

__END__

=head1 NAME

find_crisprs.pl - retrieve crisprs from WGE

=head1 SYNOPSIS

find_crisprs.pl [options]

    --species            mouse or human
    --ids                crispr ids or exon ids
    --flank              how much to flank exon ids by (default is 0) [optional]
    --fq-file            the file to dump fq data into
    --crispr-yaml-file   crispr yaml file to dump crispr data into
    --help               show this dialog

Example usage:

find_crisprs.pl --species human --crispr-yaml-file crisprs.yaml --fq-file crisprs.fq --ids 53478 23472 23567
find_crisprs.pl --species human --crispr-yaml-file crisprs.yaml --fq-file crisprs.fq --ids ENSE00001425722 ENSE00003611020 --flank 200

=head1 DESCRIPTION

Given a list of crispr ids dump out the sequence and create the YAML files necessary
to drive the paired crispr pipeline

=head AUTHOR

Alex Hodgkins

=cut
