package WebGUI::Asset::WikiPage;

# -------------------------------------------------------------------
#  WebGUI is Copyright 2001-2012 Plain Black Corporation.
# -------------------------------------------------------------------
#  Please read the legal notices (docs/legal.txt) and the license
#  (docs/license.txt) that came with this distribution before using
#  this software.
# -------------------------------------------------------------------
#  http://www.plainblack.com                     info@plainblack.com
# -------------------------------------------------------------------

use strict;

use Moose;
use WebGUI::Definition::Asset;
extends 'WebGUI::Asset';

define assetName => ['assetName', 'Asset_WikiPage'];
define icon      => 'wikiPage.gif';
define tableName => 'WikiPage';

property content => (
            label        => ['contentLabel', 'Asset_WikiPage'],
            fieldType    => "HTMLArea",
            default      => undef
         );
property views => (
            fieldType  => "integer",
            default    => 0,
            noFormPost => 1
         );
property isProtected => (
            fieldType  => "yesNo",
            default    => 0,
            noFormPost => 1
         );
property actionTaken => (
            fieldType  => "text",
            default    => '',
            noFormPost => 1,
         );
property actionTakenBy => (
            fieldType  => "user",
            default    => '',
            noFormPost => 1,
         );
property isFeatured => (
            fieldType  => "yesNo",
            default    => 0,
            noFormPost => 1,
         );

override _default_title => sub {
    my $self = shift;
    my $title = $self->session->form->get('title') || super();
    return $title;
};

with 'WebGUI::Role::Asset::AlwaysHidden';
with 'WebGUI::Role::Asset::Subscribable';
with 'WebGUI::Role::Asset::Comments';
with 'WebGUI::Role::Asset::AutoSynopsis';

use WebGUI::International;

use WebGUI::VersionTag;


#-------------------------------------------------------------------

=head2 addChild ( )

You can't add children to a wiki page.

=cut

sub addChild {
	return undef;
}

#-------------------------------------------------------------------

=head2 canAdd ($session)

This functions as a class or an object method.  It sets the subclassGroupId to 7
instead of the default of 12.

=cut

around canAdd => sub {
    my $orig  = shift;
    my $class = shift;
    my $session = shift;
    return $class->$orig($session, undef, '7');
};

#-------------------------------------------------------------------

=head2 canEdit 

Returns true if the current user can administer the wiki containing this WikiPage, or
if the current user can edit wiki pages and is trying to add or edit pages, or the page
is not protected.

=cut

sub canEdit {
	my $self = shift;
    my $wiki = $self->getWiki;
    return undef unless defined $wiki;

	my $form      = $self->session->form;
    my $addNew    = $form->process("func"              ) eq "add";
    my $editSave  = $form->process("assetId"           ) eq "new"
                 && $form->process("func"              ) eq "addSave"
                 && $form->process("className","className" ) eq "WebGUI::Asset::WikiPage";
    return $wiki->canAdminister
        || ( $wiki->canEditPages && ( $addNew || $editSave || !$self->isProtected) );
}

#-------------------------------------------------------------------

=head2 getAutoCommitWorkflowId 

Overrides the master class to handle spam prevention.  If the content matches any of
the spamStopWords, then the commit is canceled and the content is rolled back to the
previous version.  Otherwise, it returns the autoCommitWorkflowId for the regular asset
commit flow to handle.

=cut

sub getAutoCommitWorkflowId {
	my $self = shift;
    my $wiki = $self->getWiki;
    if ($wiki->hasBeenCommitted) {

        # delete spam
        my $spamStopWords = $self->session->config->get('spamStopWords');
        if (ref $spamStopWords eq 'ARRAY' && @{ $spamStopWords }) {
            my $spamRegex = join('|',@{$spamStopWords});
            $spamRegex =~ s/\s/\\ /g;
            if ($self->content =~ m{$spamRegex}xmsi) {
                my $tag = WebGUI::VersionTag->new($self->session, $self->assetId);
                $self->purgeRevision;
                if ($tag->getAssetCount == 0) {
                    $tag->rollback;
                }
                return undef;
            }
        }

        return $wiki->approvalWorkflow
            || $self->session->setting->get('defaultVersionTagWorkflow');
    }
    return undef;
}


#-------------------------------------------------------------------

=head2 getEditTemplate 

Renders a templated edit form for adding or editing a wiki page.

=cut

sub getEditTemplate {
	my $self = shift;
	my $session = $self->session;
	my $form = $session->form;
	my $i18n = WebGUI::International->new($session, "Asset_WikiPage");
	my $wiki = $self->getWiki;
	my $url = ($self->getId eq "new") ? $wiki->getUrl : $self->getUrl;
    use WebGUI::Form::HTMLArea;
    use WebGUI::Form::Submit;
    use WebGUI::Form::YesNo;
    use WebGUI::Form::Hidden;
    use WebGUI::Form::Keywords;
    use WebGUI::Form::Attachments;
	my $var = {
		title=> $i18n->get("editing")." ".(defined($self->title)? $self->title : $i18n->get("assetName")),
		formHeader => WebGUI::Form::formHeader($session, { action => $url}) 
			.WebGUI::Form::Hidden->new($session, { name => 'func', value => ( $self->getId eq 'new' ? 'addSave' : 'editSave' ) })->toHtml 
			.WebGUI::Form::Hidden->new($session, { name=>"proceed", value=>"showConfirmation" })->toHtml,
	 	formTitle => WebGUI::Form::Text->new($session, { name => 'title', maxlength => 255, size => 40, 
                value => $self->title, defaultValue=>$form->get("title","text") })->toHtml,
		formContent => WebGUI::Form::HTMLArea->new($session, { name => 'content', richEditId => $wiki->richEditor, value => $self->content })->toHtml ,
		formSubmit => WebGUI::Form::Submit->new($session, { value => 'Save' })->toHtml,
		formProtect => WebGUI::Form::YesNo->new($session, { name => "isProtected", value=>$self->isProtected})->toHtml,
                formFeatured => WebGUI::Form::YesNo->new( $session, { name => 'isFeatured', value=>$self->isFeatured})->toHtml,
        formKeywords => WebGUI::Form::Keywords->new($session, {
            name    => "keywords",
            value   => WebGUI::Keyword->new($session)->getKeywordsForAsset({asset=>$self}),
            })->toHtml,
		allowsAttachments => $wiki->allowAttachments,
		formFooter => WebGUI::Form::formFooter($session),
		isNew => ($self->getId eq "new"),
		canAdminister => $wiki->canAdminister,
		deleteConfirm => $i18n->get("delete page confirmation"),
		deleteLabel => $i18n->get("deleteLabel"),
		deleteUrl => $self->getUrl("func=delete"),
		titleLabel => $i18n->get("titleLabel"),
		contentLabel => $i18n->get("contentLabel"),
		attachmentLabel => $i18n->get("attachmentLabel"),
		protectQuestionLabel => $i18n->get("protectQuestionLabel"),
		isProtected => $self->isProtected
		};
    my $children = [];
	if ($self->getId eq "new") {
		$var->{formHeader} .= WebGUI::Form::Hidden->new($session, { name=>"assetId", value=>"new" })->toHtml 
			.WebGUI::Form::Hidden->new($session, { name=>"className", value=>$form->process("className","className") })->toHtml;
	} else {
        $children = $self->getLineage(["children"]);
    }
    $var->{formAttachment} = WebGUI::Form::Attachments->new($session, { 
        value           => $children,
        maxAttachments  => $wiki->allowAttachments,
        maxImageSize    => $wiki->maxImageSize,
        thumbnailSize   => $wiki->thumbnailSize,
        })->toHtml;
    my $template    = WebGUI::Asset->newById( $session, $wiki->pageEditTemplateId );
    $template->style( $wiki->getStyleTemplateId );
    $template->setParam( %$var );
    return $template;
}

#-------------------------------------------------------------------

=head2 getSubscriptionTemplate ( )

=cut

sub getSubscriptionTemplate { 
    my ( $self ) = @_;
    return $self->getParent->getSubscriptionTemplate;
}

#-------------------------------------------------------------------

=head2 getTemplateVars ( )

Get the common template vars for this asset

=cut

sub getTemplateVars {
    my ( $self ) = @_;
    my $session  = $self->session;
    my $i18n     = WebGUI::International->new($session, "Asset_WikiPage");
    my $wiki     = $self->getWiki;
    my $owner    = WebGUI::User->new( $session, $self->ownerUserId );
    my $keyObj   = WebGUI::Keyword->new($session);

    my $keywords    = $keyObj->getKeywordsForAsset({
        asset       => $self,
        asArrayRef  => 1,
    });

    my @keywordsLoop = ();
    foreach my $word (@{$keywords}) {
        push @keywordsLoop, {
            keyword => $word,
            url     => $wiki->getUrl("func=byKeyword;keyword=".$word),
        };
    }
    my $var = {
        %{ $self->get },
        url                 => $self->getUrl,
        keywordsLoop        => \@keywordsLoop,
        viewLabel           => $i18n->get("viewLabel"),
        editLabel           => $i18n->get("editLabel"),
        historyLabel        => $i18n->get("historyLabel"),
        wikiHomeLabel       => $i18n->get("wikiHomeLabel", "Asset_WikiMaster"),
        searchLabel         => $i18n->get("searchLabel", "Asset_WikiMaster"),	
        searchUrl           => $wiki->getUrl("func=search"),
        recentChangesUrl    => $wiki->getUrl("func=recentChanges"),
        recentChangesLabel  => $i18n->get("recentChangesLabel", "Asset_WikiMaster"),
        mostPopularUrl      => $wiki->getUrl("func=mostPopular"),
        mostPopularLabel    => $i18n->get("mostPopularLabel", "Asset_WikiMaster"),
        wikiHomeUrl         => $wiki->getUrl,
        historyUrl          => $self->getUrl("func=getHistory"),
        editContent         => $self->getEditForm,
        allowsAttachments   => $wiki->allowAttachments,
        comments            => $self->getFormattedComments,
        canEdit             => $self->canEdit,
        canAdminister       => $wiki->canAdminister,
		isProtected         => $self->isProtected,
        content             => $wiki->autolinkHtml(
            $self->scrubContent,
            {skipTitles => [$self->title]},
        ),	
        isSubscribed        => $self->isSubscribed,
        subscribeUrl        => $self->getSubscribeUrl,
        unsubscribeUrl      => $self->getUnsubscribeUrl,
        owner               => $owner->get('alias'),
    };
    return $var;
}

#-------------------------------------------------------------------

=head2 getWiki 

Returns an object referring to the wiki that contains this page.  If it is not a WikiMaster,
or the parent is undefined, it returns undef.

=cut

sub getWiki {
	my $self = shift;
	my $parent = $self->getParent;
	return undef unless defined $parent and $parent->isa('WebGUI::Asset::Wobject::WikiMaster');
	return $parent;
}

#-------------------------------------------------------------------

=head2 indexContent 

Extends the master class to handle indexing the wiki content.

=cut

around indexContent => sub {
	my $orig = shift;
	my $self = shift;
	my $indexer = $self->$orig(@_);
	$indexer->addKeywords($self->content);
	return $indexer;
};

#-------------------------------------------------------------------

=head2 preparePageTemplate 

This is essentially prepareView, but is smart and will only do the template
preparation once.  Returns the preparted page template.

=cut

sub preparePageTemplate {
	my $self = shift;
	return $self->{_pageTemplate} if $self->{_pageTemplate};
	$self->{_pageTemplate} =
	    WebGUI::Asset::Template->newById($self->session, $self->getWiki->pageTemplateId);
	$self->{_pageTemplate}->prepare;
	return $self->{_pageTemplate};
}

#-------------------------------------------------------------------

=head2 prepareView 

Extends the master class to handle preparing the main view template for the page.

=cut

override prepareView => sub {
	my $self = shift;
	super();
	$self->preparePageTemplate;
};


#-------------------------------------------------------------------

=head2 processEditForm 

Extends the master method to handle properties and attachments.

=cut

override processEditForm => sub {
    my $self    = shift;
    my $session = $self->session;
    super();
    my $actionTaken = ($session->form->process("assetId") eq "new") ? "Created" : "Edited";
    my $wiki = $self->getWiki;
    my $properties = {
        groupIdView     => $wiki->groupIdView,
        groupIdEdit     => $wiki->groupToAdminister,
        actionTakenBy   => $session->user->userId,
        actionTaken     => $actionTaken,
    };

    if ($wiki->canAdminister) {
        $properties->{isProtected} = $session->form->get("isProtected");
        $properties->{isFeatured}  = $session->form->get("isFeatured");
    }

    ($properties->{synopsis}) = $self->getSynopsisAndContent(undef, $self->get('content'));

	$self->update($properties);

    # deal with attachments from the attachments form control
    my $options = {
        maxImageSize    => $wiki->maxImageSize,
        thumbnailSize   => $wiki->thumbnailSize,
    };
    my @attachments = $session->form->param("attachments");
    my @tags = ();
    foreach my $assetId (@attachments) {
        my $asset = WebGUI::Asset->newById($session, $assetId);
        if (defined $asset) {
            unless ($asset->parentId eq $self->getId) {
                $asset->setParent($self);
                $asset->update({
                    ownerUserId => $self->ownerUserId,
                    groupIdEdit => $self->groupIdEdit,
                    groupIdView => $self->groupIdView,
                    });
            }
            $asset->applyConstraints($options);
            push(@tags, $asset->tagId);
            $asset->setVersionTag($self->tagId);
        }
    }

    # clean up empty tags
    foreach my $tag (@tags) {
        my $version = WebGUI::VersionTag->new($self->session, $tag);
        if (defined $version) {
            if ($version->getAssetCount == 0) {
                $version->rollback;
            }
        }
    }
};

#-------------------------------------------------------------------

=head2 scrubContent ( [ content ] )

Uses WikiMaster settings to remove unwanted markup and apply site wide replacements.

=head3 content

Optionally pass the ontent that we want to run the filters on.  Otherwise we get it from self.

=cut

sub scrubContent {
        my $self = shift;
        my $content = shift || $self->content;

        $content =~ s/\^-\;//g;
        my $scrubbedContent = WebGUI::HTML::filter($content, $self->getWiki->get("filterCode"));

        if ($self->getWiki->useContentFilter) {
                $scrubbedContent = WebGUI::HTML::processReplacements($self->session, $scrubbedContent);
        }

        return $scrubbedContent;
}

#-------------------------------------------------------------------

=head2 valid_parent_classes

Make sure that the current session asset is a WikiMaster for pasting and adding checks.

This is a class method.

=cut

sub valid_parent_classes {
    return [qw/WebGUI::Asset::Wobject::WikiMaster/];
}

#-------------------------------------------------------------------

=head2 view 

Renders this asset.

=cut

sub view {
	my $self = shift;
	return $self->processTemplate($self->getTemplateVars, $self->getWiki->pageTemplateId);
}

#-------------------------------------------------------------------

=head2 www_delete 

Overrides the master method so that privileges are checked on the parent wiki instead
of the page.  Returns the user to viewing the wiki.

=cut

sub www_delete {
	my $self = shift;
	return $self->session->privilege->insufficient unless $self->getWiki->canAdminister;
	$self->trash;
	$self->session->asset($self->getParent);
	return $self->getParent->www_view;
}

#-------------------------------------------------------------------

=head2 www_getHistory 

Returns the version history of this wiki page.  The output is templated.

=cut

sub www_getHistory {
	my $self = shift;
	return $self->session->privilege->insufficient unless $self->canEdit;
	my $var = {};
	my ($icon, $date) = $self->session->quick(qw(icon datetime));
	my $i18n = WebGUI::International->new($self->session, 'Asset_WikiPage');
	foreach my $revision (@{$self->getRevisions}) {
		my $user = WebGUI::User->new($self->session, $revision->get("actionTakenBy"));
		push(@{$var->{pageHistoryEntries}}, {
			toolbar => $icon->delete("func=purgeRevision;revisionDate=".$revision->revisionDate, $revision->url, $i18n->get("delete confirmation"))
                        	.$icon->edit('func=edit;revision='.$revision->revisionDate, $revision->url)
                        	.$icon->view('func=view;revision='.$revision->revisionDate, $revision->url),
			date => $date->epochToHuman($revision->revisionDate),
			username => $user->get('alias') || $user->username,
			actionTaken => $revision->actionTaken,
			interval => join(" ", $date->secondsToInterval(time() - $revision->revisionDate))
			});		
	}
	return $self->processTemplate($var, $self->getWiki->pageHistoryTemplateId);
}

#-------------------------------------------------------------------

=head2 www_purgeRevision

Override the main method to change which group is allowed to purge revisions for WikiPages.  Only
members who can administer the parent wiki (canAdminister) can purge revisions.

=cut

sub www_purgeRevision {
	my $self    = shift;
	my $session = $self->session;
	return $session->privilege->insufficient() unless $self->getWiki->canAdminister;
	my $revisionDate = $session->form->process("revisionDate");
	return undef unless $revisionDate;
	my $asset = WebGUI::Asset->new($session, $self->getId, $self->get("className"), $revisionDate);
	return undef if ($asset->get('revisionDate') != $revisionDate);
	my $parent = $asset->getParent;
	$asset->purgeRevision;
	if ($session->form->process("proceed") eq "manageRevisionsInTag") {
		my $working = (defined $self) ? $self : $parent;
		$session->response->setRedirect($working->getUrl("op=manageRevisionsInTag"));
		return undef;
	}
	unless (defined $self) {
		return $parent->www_view;
	}
	return $self->www_manageRevisions;
}

#-------------------------------------------------------------------

=head2 www_restoreWikiPage 

Publishes a wiki page that has been put into the trash or the clipboard.

=cut

sub www_restoreWikiPage {
	my $self = shift;
	return $self->session->privilege->insufficient unless $self->getWiki->canAdminister;
	$self->publish;	
	return $self->www_view;
}


#-------------------------------------------------------------------

=head2 www_showConfirmation ( )

Shows a confirmation message letting the user know their page has been submitted.

=cut

sub www_showConfirmation {
	my $self = shift;
	my $i18n = WebGUI::International->new($self->session, "Asset_WikiPage");
	return $self->getWiki->processStyle('<p>'.$i18n->get("page received").'</p><p><a href="'.$self->getWiki->getUrl.'">'.$i18n->get("493","WebGUI").'</a></p>');
}

#-------------------------------------------------------------------

=head2 www_view 

Override the master method to count the number of times this page has been viewed,
and to render it with the parent's style.

=cut

sub www_view {
	my $self = shift;
	return $self->session->privilege->noAccess unless $self->canView;
	$self->update({ views => $self->views+1 });
	# TODO: This should probably exist, as the CS has one.
#	$self->session->response->setCacheControl($self->getWiki->get('visitorCacheTimeout'))
#	    if ($self->session->user->isVisitor);
	$self->session->response->sendHeader;
	$self->prepareView;
	return $self->getWiki->processStyle($self->view);
}


__PACKAGE__->meta->make_immutable;
1;
