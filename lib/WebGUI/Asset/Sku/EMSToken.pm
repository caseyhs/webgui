package WebGUI::Asset::Sku::EMSToken;

=head1 LEGAL

 -------------------------------------------------------------------
  WebGUI is Copyright 2001-2008 Plain Black Corporation.
 -------------------------------------------------------------------
  Please read the legal notices (docs/legal.txt) and the license
  (docs/license.txt) that came with this distribution before using
  this software.
 -------------------------------------------------------------------
  http://www.plainblack.com                     info@plainblack.com
 -------------------------------------------------------------------

=cut

use strict;
use Tie::IxHash;
use base 'WebGUI::Asset::Sku';



=head1 NAME

Package WebGUI::Asset::Sku::EMSToken

=head1 DESCRIPTION

A token for the Event Manager. Tokens are like convention currency.

=head1 SYNOPSIS

use WebGUI::Asset::Sku::EMSToken;

=head1 METHODS

These methods are available from this class:

=cut


#-------------------------------------------------------------------

=head2 definition

Adds price field.

=cut

sub definition {
	my $class = shift;
	my $session = shift;
	my $definition = shift;
	my %properties;
	tie %properties, 'Tie::IxHash';
	my $i18n = WebGUI::International->new($session, "Asset_EventManagementSystem");
	my $date = WebGUI::DateTime->new($session, time());
	%properties = (
		price => {
			tab             => "commerce",
			fieldType       => "float",
			defaultValue    => 0.00,
			label           => $i18n->get("price"),
			hoverHelp       => $i18n->get("price help"),
			},
	    );
	push(@{$definition}, {
		assetName           => $i18n->get('ems token'),
		icon                => 'EMSToken.gif',
		autoGenerateForms   => 1,
		tableName           => 'EMSToken',
		className           => 'WebGUI::Asset::Sku::EMSToken',
		properties          => \%properties
	    });
	return $class->SUPER::definition($session, $definition);
}


#-------------------------------------------------------------------

=head2 getConfiguredTitle

Returns title + badgeholder name.

=cut

sub getConfiguredTitle {
    my $self = shift;
	my $name = $self->session->db->getScalar("select name from EMSRegistrant where badgeId=?",[$self->getOptions->{badgeId}]);
    return $self->getTitle." (".$name.")";
}

#-------------------------------------------------------------------

=head2 getPrice

Returns the value of the price field.

=cut

sub getPrice {
    my $self = shift;
    return $self->get("price");
}

#-------------------------------------------------------------------

=head2 onCompletePurchase

Adds tokens to the badge.

=cut

sub onCompletePurchase {
	my ($self, $item) = @_;
	my $db = $self->session->db;
	my @params = ($self->getId, $self->getOptions->{badgeId});
	my $currentQuantity = $db->quickScalar("select quantity from EMSRegistrantToken where tokenAssetId=? and badgeId=?",\@params);
	unshift @params, $item->get("quantity");
	if (defined $currentQuantity) {
		$db->write("update EMSRegistrationToken set quantity=quantity+? where tokenAssetId=? and badgeId=?",\@params);
	}
	else {
		$db->write("insert into EMSRegistrationToken (quantity, tokenAssetId, badgeId) values (?,?,?)",\@params);
	}
	return undef;
}

#-------------------------------------------------------------------

=head2 purge

Destroys all tokens of this type. No refunds are given.

=cut

sub purge {
	my $self = shift;
	$self->session->db->write("delete from EMSRegistrantToken where tokenAssetId=?",[$self->getId]);
	$self->SUPER::purge;
}

#-------------------------------------------------------------------

=head2 view

Displays the token description.

=cut

sub view {
	my ($self) = @_;
	
	# build objects we'll need
	my $i18n = WebGUI::International->new($self->session, "Asset_EventManagementSystem");
	my $form = $self->session->form;
		
	
	# render the page;
	my $output = '<h1>'.$self->getTitle.'</h1>'
		.'<p>'.$self->get('description').'</p>';

	# build the add to cart form
	if ($form->get('badgeId') ne '') {
		my $addToCart = WebGUI::HTMLForm->new($self->session, action=>$self->getUrl);
		$addToCart->hidden(name=>"func", value=>"addToCart");
		$addToCart->hidden(name=>"badgeId", value=>$form->get('badgeId'));
		$addToCart->integer(name=>'quantity', value=>1, label=>$i18n->get('quantity','Shop'));
		$addToCart->submit(value=>$i18n->get('add to cart','Shop'), label=>$self->getPrice);
		$output .= $addToCart->print;		
	}
		
	return $output;
}

#-------------------------------------------------------------------

=head2 www_addToCart

Takes form variable badgeId and add the token to the cart.

=cut

sub www_addToCart {
	my ($self) = @_;
	return $self->session->privilege->noAccess() unless $self->getParent->canView;
	my $badgeId = $self->session->form->get('badgeId');
	$self->addToCart({badgeId=>$badgeId});
	return $self->getParent->www_viewExtras($badgeId);
}


1;
