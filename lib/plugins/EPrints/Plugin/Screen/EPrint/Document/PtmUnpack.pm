=head1 NAME

EPrints::Plugin::Screen::EPrint::Document::PtmUnpack

=cut

package EPrints::Plugin::Screen::EPrint::Document::PtmUnpack;

use base qw( EPrints::Plugin::Screen::EPrint::Document::Unpack );

use strict;

sub new
{
	my( $class, %params ) = @_;

	my $self = $class->SUPER::new(%params);

	$self->{icon} = "action_ptmunpack.png";

	$self->{appears} = [
		{
			place => "document_item_actions",
			position => 90,
		},
	];
	
	$self->{actions} = [qw/ cancel unpack /];

	$self->{ajax} = "interactive";

	$self->{disable} = 0; # default to enable

	return $self;
}

sub allow_cancel { 1 }
sub allow_unpack { shift->can_be_viewed( @_ ) }

sub can_be_viewed
{
	my( $self ) = @_;

	my $doc = $self->{processor}->{document};
	return 0 if !$doc;

	return 0 if !$doc->is_set( "mime_type" );

	return 0 if !$self->SUPER::can_be_viewed;

	return 0 if $doc->value( "mime_type" ) ne "application/zip";

	my @plugins = grep {
		$_->can_produce( "dataobj/document" )
	} $self->{session}->get_plugins(
		type => "Import",
		can_accept => $doc->value( "mime_type" ),
	);

	return scalar(@plugins) > 0;
}

sub render
{
	my( $self ) = @_;

	my $doc = $self->{processor}->{document};

	my $frag = $self->{session}->make_doc_fragment;

	my $div = $self->{session}->make_element( "div", class=>"ep_block" );
	$frag->appendChild( $div );

	$div->appendChild( $self->render_document( $doc ) );

	$div = $self->{session}->make_element( "div", class=>"ep_block" );
	$frag->appendChild( $div );

	$div->appendChild( $self->html_phrase( "help" ) );
	
	my %buttons = (
		cancel => $self->{session}->phrase(
				"lib/submissionform:action_cancel" ),
		unpack => $self->phrase( "action_unpack" ),
		_order => [ qw( unpack cancel ) ]
	);

	my $form= $self->render_form;
	$form->appendChild( 
		$self->{session}->render_action_buttons( 
			%buttons ) );
	$div->appendChild( $form );

	return( $frag );
}	

sub action_unpack
{
	my( $self ) = @_;

	$self->{processor}->{redirect} = $self->{processor}->{return_to}
		if !$self->wishes_to_export;

	my $eprint = $self->{processor}->{eprint};
	my $doc = $self->{processor}->{document};

	return if !$doc;

	$self->_expand( $doc->get_dataset );
}

sub _expand
{
	my( $self, $dataset ) = @_;

	my $eprint = $self->{processor}->{eprint};
	my $doc = $self->{processor}->{document};

	return if !$doc;

	# we ask the plugin to import into either documents or eprints
	# -> produce a single document or
	# -> produce lots of documents
	# the normal epdata_to_dataobj is intercepted (parse_only=>1) and we merge
	# the new documents into our eprint
	my $handler = EPrints::CLIProcessor->new(
		message => sub { $self->{processor}->add_message( $_[0], $self->{session}->make_text( $_[1] ) ) },
		epdata_to_dataobj => sub {
			my( $epdata ) = @_;

			my @items;

			my %parts;

			foreach my $file (@{$epdata->{files}})
			{
				if ($file->{filename} =~ /\.xml$/) {
					push @items, $eprint->create_subdataobj( "documents", {
						main => $file->{filename},
						format => "other",
						formatdesc => "Polynomial Texture Map configuration",
						mime_type => "application/xml",
						files => [$file],
					});
				}
				elsif ($file->{filename} =~ m{([^/]+)/[^/]+$}) {
					push @{$parts{$1}}, $file;
				}
			}

			if ($parts{'snapshots'}) {
				foreach my $file (@{$parts{'snapshots'}})
				{
					if ($file->{filename} =~ m{/(snapshot\.jpg)$}) {
						$file->{filename} = $1;
						push @items, $eprint->create_subdataobj( "documents", {
							main => $file->{filename},
							format => "image",
							formatdesc => "Snapshot",
							mime_type => "image/jpeg",
							files => [$file],
						});
						last;
					}
				}
			}
			elsif ($parts{'MuseumLighting'}) {
				my $file = $parts{'MuseumLighting'}[0];
				if ($file->{filename} =~ m{/([^/]+\.jpg)$}) {
					$file->{filename} = $1;
					push @items, $eprint->create_subdataobj( "documents", {
						main => $file->{filename},
						format => "image",
						formatdesc => "Snapshot",
						mime_type => "image/jpeg",
						files => [$file],
					});
					last;
				}
			}

			if ($parts{'finished-files'}) {
				my $file = $parts{'finished-files'}[0];
				$file->{filename} =~ s{^.*/}{};
				push @items, $eprint->create_subdataobj( "documents", {
					main => $file->{filename},
					format => "other",
					formatdesc => "Polynomial Texture Map (PTM)",
					mime_type => "application/octet-stream",
					files => [$file],
				});
			}

			if ($parts{'original-captures'}) {
				my $files = $parts{'original-captures'};
				foreach my $file (@$files)
				{
					$file->{filename} =~ s{^.*/}{};
				}
				my $file = $files->[0];
				my $epdata = {
					main => $file->{filename},
					formatdesc => "Source Images",
					files => $files,
				};
				$self->{session}->run_trigger( EPrints::Const::EP_TRIGGER_MEDIA_INFO,
						filepath => "$file->{_content}",
						filename => $file->{filename},
						epdata => $epdata,
					);
				push @items, $eprint->create_subdataobj( "documents", $epdata );
			}
			elsif ($parts{'jpeg-exports'}) {
				my $files = $parts{'jpeg-exports'};
				foreach my $file (@$files)
				{
					$file->{filename} =~ s{^.*/}{};
				}
				push @items, $eprint->create_subdataobj( "documents", {
					main => $files->[0]{filename},
					format => "image",
					formatdesc => "Source Images",
					mime_type => "image/jpeg",
					files => $files,
				});
			}

			return $items[$#items];
		},
	);

	my( $plugin ) = grep {
		$_->can_produce( "dataobj/document" )
	} $self->{session}->get_plugins({
			Handler => $handler,
			parse_only => 1,
		},
		type => "Import",
		can_accept => $doc->value( "mime_type" ),
	);

	return if !$plugin;

	my $file = $doc->stored_file( $doc->value( "main" ) );
	return if !$file;

	my $fh = $file->get_local_copy;

	my $list = $plugin->input_fh(
		fh => $fh,
		dataset => $dataset,
		filename => $file->value( "filename" ),
		mime_type => $file->value( "mime_type" ),
		actions => [qw( unpack )],
	);
	return if !$list || !$list->count;

	$self->{processor}->{redirect} .= "&docid=".$list->item( 0 )->id
		if !$self->wishes_to_export;

	return 1;
}

1;

=head1 COPYRIGHT

=for COPYRIGHT BEGIN

Copyright 2000-2011 University of Southampton.

=for COPYRIGHT END

=for LICENSE BEGIN

This file is part of EPrints L<http://www.eprints.org/>.

EPrints is free software: you can redistribute it and/or modify it
under the terms of the GNU Lesser General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

EPrints is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
License for more details.

You should have received a copy of the GNU Lesser General Public
License along with EPrints.  If not, see L<http://www.gnu.org/licenses/>.

=for LICENSE END

