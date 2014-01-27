package WGE::Model::Plugin::User;

use Moose::Role;
use Hash::MoreUtils qw(slice_def);
use Log::Log4perl qw( :easy );

sub user_id_for{
    my ($self, $name) = @_;

    my $user = $self->schema->resultset('User')->find({ name => $name});
    return $user->id;
}

1;